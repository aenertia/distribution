// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)
//
// ssc-iio-bridge: Qualcomm SLPI sensor to Linux IIO device bridge
// AP <-- QRTR/QMI --> SLPI DSP,  AP <-- IIO configfs --> /dev/iio:deviceN
//
// Protocol layers (innermost to outermost):
//   1. Protobuf (proto2): SscClientRequest / SscClientResponse
//   2. QMI TLV: 7-byte SDU header + TLV fields
//   3. AF_QIPCRTR datagram: QRTR transport to SLPI DSP

#include <sys/socket.h>
#include <linux/qrtr.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <endian.h>

/* ---------- SSC QMI constants ---------- */

#define SSC_QMI_SERVICE_ID    0x190   /* SSC service on QRTR name server */
#define SSC_QMI_VERSION       1

/* QMI SDU message IDs for SSC */
#define SSC_QMI_MSG_CONTROL   0x0020  /* Request: send protobuf to SSC */
#define SSC_QMI_MSG_REPORT_SM 0x0021  /* Indication: small report */
#define SSC_QMI_MSG_REPORT_LG 0x0022  /* Indication: large report */

/* QMI SDU message types (byte 0 of QMI header) */
#define QMI_TYPE_REQUEST      0x00
#define QMI_TYPE_RESPONSE     0x02
#define QMI_TYPE_INDICATION   0x04

/* SSC protobuf message IDs */
#define SSC_MSG_REQUEST_SUID  512     /* 0x200 - SUID lookup request */
#define SSC_MSG_RESPONSE_SUID 768     /* 0x300 - SUID lookup response */

/* Well-known SUID for the SUID Lookup Service (128-bit) */
#define SUID_LOOKUP_LOW       0xABABABABABABABABULL
#define SUID_LOOKUP_HIGH      0xABABABABABABABABULL

/* Timeouts */
#define QRTR_LOOKUP_TIMEOUT_MS   3000
#define SSC_RESPONSE_TIMEOUT_MS  5000

/* ---------- Data types ---------- */

struct ssc_uid {
	uint64_t low;
	uint64_t high;
};

/* ---------- Protobuf wire format helpers ---------- */
/*
 * Minimal protobuf decoder for proto2 messages.
 * Only handles the wire types we need: varint(0), fixed64(1),
 * length-delimited(2), fixed32(5).
 */

#define PB_WIRE_VARINT  0
#define PB_WIRE_64BIT   1
#define PB_WIRE_LEN     2
#define PB_WIRE_32BIT   5

static int pb_decode_varint(const uint8_t *buf, size_t len,
			    uint64_t *val, size_t *consumed)
{
	uint64_t result = 0;
	size_t i;

	for (i = 0; i < len && i < 10; i++) {
		result |= (uint64_t)(buf[i] & 0x7F) << (7 * i);
		if (!(buf[i] & 0x80)) {
			*val = result;
			*consumed = i + 1;
			return 0;
		}
	}
	return -1; /* truncated */
}

/*
 * Skip a protobuf field value based on wire type.
 * Returns bytes consumed, or 0 on error.
 */
static size_t pb_skip_value(const uint8_t *buf, size_t len, int wire_type)
{
	uint64_t val;
	size_t consumed;

	switch (wire_type) {
	case PB_WIRE_VARINT:
		if (pb_decode_varint(buf, len, &val, &consumed) < 0)
			return 0;
		return consumed;
	case PB_WIRE_64BIT:
		return len >= 8 ? 8 : 0;
	case PB_WIRE_32BIT:
		return len >= 4 ? 4 : 0;
	case PB_WIRE_LEN:
		if (pb_decode_varint(buf, len, &val, &consumed) < 0)
			return 0;
		if (consumed + val > len)
			return 0;
		return consumed + (size_t)val;
	default:
		return 0;
	}
}

/*
 * Find a field by number in a protobuf message buffer.
 * Returns pointer to the field's value data.
 * For LEN fields, the pointer is AFTER the length varint (points to content).
 * Sets *wire_type and *out_len.
 * Returns NULL if not found.
 */
static const uint8_t *pb_find_field(const uint8_t *buf, size_t len,
				    uint32_t field_num, int *wire_type,
				    size_t *out_len)
{
	size_t off = 0;

	while (off < len) {
		uint64_t tag;
		size_t consumed;

		if (pb_decode_varint(buf + off, len - off, &tag, &consumed) < 0)
			break;
		off += consumed;

		uint32_t fnum = (uint32_t)(tag >> 3);
		int wtype = (int)(tag & 0x07);

		if (fnum == field_num) {
			*wire_type = wtype;
			switch (wtype) {
			case PB_WIRE_LEN: {
				uint64_t flen;

				if (pb_decode_varint(buf + off, len - off,
						     &flen, &consumed) < 0)
					return NULL;
				off += consumed;
				*out_len = (size_t)flen;
				return buf + off;
			}
			case PB_WIRE_64BIT:
				*out_len = 8;
				return buf + off;
			case PB_WIRE_32BIT:
				*out_len = 4;
				return buf + off;
			case PB_WIRE_VARINT: {
				uint64_t v;

				if (pb_decode_varint(buf + off, len - off,
						     &v, &consumed) < 0)
					return NULL;
				*out_len = consumed;
				return buf + off;
			}
			default:
				return NULL;
			}
		}

		/* Skip this field's value */
		size_t skip = pb_skip_value(buf + off, len - off, wtype);

		if (skip == 0)
			break;
		off += skip;
	}
	return NULL;
}

/*
 * Iterate repeated fields with the same field number.
 * Start with *offset = 0. Each call advances *offset.
 * Returns pointer to field value data, sets *wire_type and *out_len.
 * Returns NULL when no more instances found.
 */
static const uint8_t *pb_next_field(const uint8_t *buf, size_t len,
				    uint32_t field_num, size_t *offset,
				    int *wire_type, size_t *out_len)
{
	while (*offset < len) {
		uint64_t tag;
		size_t consumed;

		if (pb_decode_varint(buf + *offset, len - *offset,
				     &tag, &consumed) < 0)
			break;
		*offset += consumed;

		uint32_t fnum = (uint32_t)(tag >> 3);
		int wtype = (int)(tag & 0x07);

		if (fnum == field_num) {
			*wire_type = wtype;
			if (wtype == PB_WIRE_LEN) {
				uint64_t flen;

				if (pb_decode_varint(buf + *offset,
						     len - *offset,
						     &flen, &consumed) < 0)
					return NULL;
				*offset += consumed;
				const uint8_t *result = buf + *offset;

				*out_len = (size_t)flen;
				*offset += (size_t)flen;
				return result;
			} else if (wtype == PB_WIRE_64BIT) {
				const uint8_t *result = buf + *offset;

				*out_len = 8;
				*offset += 8;
				return result;
			} else if (wtype == PB_WIRE_32BIT) {
				const uint8_t *result = buf + *offset;

				*out_len = 4;
				*offset += 4;
				return result;
			} else if (wtype == PB_WIRE_VARINT) {
				uint64_t v;
				const uint8_t *result = buf + *offset;

				if (pb_decode_varint(buf + *offset,
						     len - *offset,
						     &v, &consumed) < 0)
					return NULL;
				*out_len = consumed;
				*offset += consumed;
				return result;
			}
			return NULL;
		}

		/* Skip other field */
		size_t skip = pb_skip_value(buf + *offset, len - *offset, wtype);

		if (skip == 0)
			break;
		*offset += skip;
	}
	return NULL;
}

/* ---------- Protobuf encoder: SUID lookup request ---------- */
/*
 * Hand-encode SscClientRequest for SUID lookup.
 *
 * Proto structure (from ssc-common.proto + ssc-sensor-suid.proto):
 *   SscClientRequest {
 *     uid = SscUid { low=0xABAB..., high=0xABAB... }
 *     msg_id = 512 (SSC_MSG_REQUEST_SUID)
 *     config = SscClientConfig { processor=1, suspend_mode=0 }
 *     request = SscClientRequestBody {
 *       msg = SscSuidRequest { data_type=<sensor_type> }
 *     }
 *   }
 *
 * Protobuf encoding reference:
 *   tag byte = (field_number << 3) | wire_type
 *   wire_type: 0=varint, 1=fixed64, 2=length-delimited, 5=fixed32
 *
 * buf must be >= 64 bytes. Returns encoded size.
 */
static size_t pb_encode_suid_request(uint8_t *buf, const char *data_type)
{
	size_t pos = 0;
	size_t dt_len = strlen(data_type);

	/* --- SscClientRequest.uid (field 1, LEN) = SscUid --- */
	buf[pos++] = 0x0a;  /* tag: field 1, wire 2 (LEN) */
	buf[pos++] = 18;    /* length: 18 bytes */
	/* SscUid.low (field 1, fixed64) = 0xABABABABABABABAB */
	buf[pos++] = 0x09;  /* tag: field 1, wire 1 (64BIT) */
	for (int i = 0; i < 8; i++)
		buf[pos++] = 0xAB;
	/* SscUid.high (field 2, fixed64) = 0xABABABABABABABAB */
	buf[pos++] = 0x11;  /* tag: field 2, wire 1 (64BIT) */
	for (int i = 0; i < 8; i++)
		buf[pos++] = 0xAB;

	/* --- SscClientRequest.msg_id (field 2, fixed32) = 512 --- */
	buf[pos++] = 0x15;  /* tag: field 2, wire 5 (32BIT) */
	buf[pos++] = 0x00;  /* 512 = 0x00000200 LE */
	buf[pos++] = 0x02;
	buf[pos++] = 0x00;
	buf[pos++] = 0x00;

	/* --- SscClientRequest.config (field 3, LEN) = SscClientConfig --- */
	buf[pos++] = 0x1a;  /* tag: field 3, wire 2 (LEN) */
	buf[pos++] = 4;     /* length: 4 bytes */
	buf[pos++] = 0x08;  /* processor (field 1, varint) */
	buf[pos++] = 0x01;  /* = 1 (SSC_PROCESSOR_APSS) */
	buf[pos++] = 0x10;  /* suspend_mode (field 2, varint) */
	buf[pos++] = 0x00;  /* = 0 (SSC_SUSPEND_MODE_WAKEUP) */

	/* --- SscClientRequest.request (field 4, LEN) = SscClientRequestBody --- */
	/*
	 * Inner payload chain:
	 *   SscClientRequestBody.msg (field 2, bytes) =
	 *     SscSuidRequest.data_type (field 1, string) = data_type
	 *
	 * SscSuidRequest: tag(0x0a) + len(dt_len) + data_type
	 * SscClientRequestBody: tag(0x12) + len(suid_req_len) + suid_req
	 */
	size_t suid_req_len = 1 + 1 + dt_len;   /* 0x0a + len + string */
	size_t req_body_len = 1 + 1 + suid_req_len; /* 0x12 + len + suid_req */

	buf[pos++] = 0x22;  /* tag: field 4, wire 2 (LEN) */
	buf[pos++] = (uint8_t)req_body_len;
	/* SscClientRequestBody.msg (field 2, bytes) */
	buf[pos++] = 0x12;  /* tag: field 2, wire 2 (LEN) */
	buf[pos++] = (uint8_t)suid_req_len;
	/* SscSuidRequest.data_type (field 1, string) */
	buf[pos++] = 0x0a;  /* tag: field 1, wire 2 (LEN) */
	buf[pos++] = (uint8_t)dt_len;
	memcpy(buf + pos, data_type, dt_len);
	pos += dt_len;

	return pos;
}

/* ---------- QMI TLV helpers ---------- */
/*
 * QMI SDU header (7 bytes, used over QRTR — no QMUX framing):
 *   byte 0:    message_type (0=request, 2=response, 4=indication)
 *   bytes 1-2: transaction_id (u16 LE)
 *   bytes 3-4: message_id (u16 LE)
 *   bytes 5-6: payload_length (u16 LE, bytes after header)
 */
#define QMI_HDR_SIZE 7

static void qmi_put_header(uint8_t *buf, uint8_t type, uint16_t txn_id,
			    uint16_t msg_id, uint16_t payload_len)
{
	buf[0] = type;
	buf[1] = (uint8_t)(txn_id & 0xFF);
	buf[2] = (uint8_t)(txn_id >> 8);
	buf[3] = (uint8_t)(msg_id & 0xFF);
	buf[4] = (uint8_t)(msg_id >> 8);
	buf[5] = (uint8_t)(payload_len & 0xFF);
	buf[6] = (uint8_t)(payload_len >> 8);
}

/*
 * Append a QMI TLV (Type-Length-Value) to buf.
 * Returns number of bytes written (3 + data_len).
 */
static size_t qmi_put_tlv(uint8_t *buf, uint8_t type,
			   const uint8_t *data, uint16_t data_len)
{
	buf[0] = type;
	buf[1] = (uint8_t)(data_len & 0xFF);
	buf[2] = (uint8_t)(data_len >> 8);
	memcpy(buf + 3, data, data_len);
	return 3 + data_len;
}

/*
 * Find a TLV by type in a QMI payload (after the 7-byte header).
 * Returns pointer to value data and sets *out_len.
 * Returns NULL if not found.
 */
static const uint8_t *qmi_find_tlv(const uint8_t *payload, size_t payload_len,
				    uint8_t type, uint16_t *out_len)
{
	size_t off = 0;

	while (off + 3 <= payload_len) {
		uint8_t t = payload[off];
		uint16_t l = payload[off + 1] |
			     ((uint16_t)payload[off + 2] << 8);

		if (off + 3 + l > payload_len)
			break;
		if (t == type) {
			*out_len = l;
			return payload + off + 3;
		}
		off += 3 + l;
	}
	return NULL;
}

/* ---------- QRTR transport ---------- */

static int qrtr_open(uint32_t *out_node, uint32_t *out_port)
{
	int fd;
	struct sockaddr_qrtr sq;
	socklen_t sl = sizeof(sq);

	fd = socket(AF_QIPCRTR, SOCK_DGRAM, 0);
	if (fd < 0) {
		fprintf(stderr, "ssc-iio-bridge: failed to open QRTR socket: %s\n",
			strerror(errno));
		return -1;
	}

	memset(&sq, 0, sizeof(sq));
	if (getsockname(fd, (struct sockaddr *)&sq, &sl) < 0) {
		fprintf(stderr, "ssc-iio-bridge: getsockname failed: %s\n",
			strerror(errno));
		close(fd);
		return -1;
	}

	*out_node = sq.sq_node;
	*out_port = sq.sq_port;

	fprintf(stdout, "ssc-iio-bridge: QRTR socket opened on node %u port %u\n",
		*out_node, *out_port);

	return fd;
}

/*
 * Discover SSC service via QRTR name server protocol.
 *
 * Sends NEW_LOOKUP (cmd=10) for service 0x190 to the in-kernel QRTR NS.
 * The NS responds with NEW_SERVER (cmd=4) for each matching service,
 * containing the remote node and port.
 *
 * Returns 0 on success (node/port populated), -1 on failure/timeout.
 */
static int qrtr_find_ssc(int fd, uint32_t *out_node, uint32_t *out_port)
{
	struct qrtr_ctrl_pkt pkt;
	struct sockaddr_qrtr dst;
	struct pollfd pfd;

	/* Send NEW_LOOKUP for SSC service */
	memset(&pkt, 0, sizeof(pkt));
	pkt.cmd = htole32(QRTR_TYPE_NEW_LOOKUP);
	pkt.server.service = htole32(SSC_QMI_SERVICE_ID);
	pkt.server.instance = 0; /* match any version/instance */
	/* node and port are zero in lookup (not used) */

	memset(&dst, 0, sizeof(dst));
	dst.sq_family = AF_QIPCRTR;
	dst.sq_node = QRTR_NODE_BCAST;
	dst.sq_port = QRTR_PORT_CTRL;

	if (sendto(fd, &pkt, sizeof(pkt), 0,
		   (struct sockaddr *)&dst, sizeof(dst)) < 0) {
		fprintf(stderr, "ssc-iio-bridge: QRTR lookup sendto failed: %s\n",
			strerror(errno));
		return -1;
	}

	fprintf(stdout, "ssc-iio-bridge: sent NEW_LOOKUP for service 0x%x\n",
		SSC_QMI_SERVICE_ID);

	/* Wait for NEW_SERVER response */
	pfd.fd = fd;
	pfd.events = POLLIN;

	while (1) {
		int ret = poll(&pfd, 1, QRTR_LOOKUP_TIMEOUT_MS);

		if (ret < 0) {
			fprintf(stderr, "ssc-iio-bridge: poll failed: %s\n",
				strerror(errno));
			return -1;
		}
		if (ret == 0) {
			fprintf(stderr,
				"ssc-iio-bridge: QRTR service lookup timed out (%d ms)\n"
				"  SSC service (0x%x) not found on QRTR bus.\n"
				"  SLPI may not have QRTR enabled, or vendor firmware\n"
				"  not installed. Check IPCRTR channel state:\n"
				"    ls /sys/bus/rpmsg/devices/*IPCRTR*\n"
				"    cat /sys/bus/rpmsg/devices/*IPCRTR*/announce\n",
				QRTR_LOOKUP_TIMEOUT_MS, SSC_QMI_SERVICE_ID);
			return -1;
		}

		struct qrtr_ctrl_pkt resp;
		struct sockaddr_qrtr src;
		socklen_t src_len = sizeof(src);

		ssize_t n = recvfrom(fd, &resp, sizeof(resp), 0,
				     (struct sockaddr *)&src, &src_len);
		if (n < 0) {
			fprintf(stderr, "ssc-iio-bridge: recvfrom failed: %s\n",
				strerror(errno));
			return -1;
		}

		/* Ignore non-control messages */
		if (src.sq_port != QRTR_PORT_CTRL)
			continue;

		if ((size_t)n < sizeof(struct qrtr_ctrl_pkt))
			continue;

		uint32_t cmd = le32toh(resp.cmd);

		if (cmd == QRTR_TYPE_NEW_SERVER) {
			uint32_t svc = le32toh(resp.server.service);

			if (svc == SSC_QMI_SERVICE_ID) {
				*out_node = le32toh(resp.server.node);
				*out_port = le32toh(resp.server.port);
				fprintf(stdout,
					"ssc-iio-bridge: SSC service found at "
					"node %u port %u (instance 0x%x)\n",
					*out_node, *out_port,
					le32toh(resp.server.instance));
				return 0;
			}
		}

		/*
		 * DEL_SERVER or other control messages: continue waiting.
		 * The NS does not send an explicit "end of list" marker;
		 * we rely on the poll timeout if no match is found.
		 */
	}
}

/* ---------- SSC QMI send/receive ---------- */

static uint16_t g_txn_id;

/*
 * Send a SUID lookup request for the given data_type (e.g. "accel", "gyro").
 *
 * Wire format:
 *   QMI SDU header (7 bytes):
 *     type=request(0), txn_id, msg_id=0x0020, payload_len
 *   TLV 0x10 (report_type): value=0x01 (large)
 *   TLV 0x01 (data): serialized SscClientRequest protobuf
 */
static int ssc_send_suid_request(int fd, uint32_t node, uint32_t port,
				 const char *data_type)
{
	uint8_t pb_buf[64];
	uint8_t qmi_buf[256];
	size_t pb_len, off;

	/* Encode protobuf */
	pb_len = pb_encode_suid_request(pb_buf, data_type);

	/* Build QMI TLV payload */
	g_txn_id++;

	/* TLV 0x10: report_type = 1 (large report) */
	uint8_t report_type = 0x01;

	/* Payload = TLV(0x10, 1 byte) + TLV(0x01, pb_len bytes) */
	uint16_t payload_len = (uint16_t)(4 + 3 + pb_len);

	/* QMI header */
	qmi_put_header(qmi_buf, QMI_TYPE_REQUEST, g_txn_id,
		       SSC_QMI_MSG_CONTROL, payload_len);
	off = QMI_HDR_SIZE;

	/* TLV 0x10 */
	off += qmi_put_tlv(qmi_buf + off, 0x10, &report_type, 1);

	/* TLV 0x01 */
	off += qmi_put_tlv(qmi_buf + off, 0x01, pb_buf, (uint16_t)pb_len);

	/* Send to SSC service */
	struct sockaddr_qrtr dst;

	memset(&dst, 0, sizeof(dst));
	dst.sq_family = AF_QIPCRTR;
	dst.sq_node = node;
	dst.sq_port = port;

	ssize_t ret = sendto(fd, qmi_buf, off, 0,
			     (struct sockaddr *)&dst, sizeof(dst));
	if (ret < 0) {
		fprintf(stderr,
			"ssc-iio-bridge: sendto SSC failed for '%s': %s\n",
			data_type, strerror(errno));
		return -1;
	}

	fprintf(stdout,
		"ssc-iio-bridge: sent SUID lookup for '%s' "
		"(txn=%u, %zu bytes QMI, %zu bytes protobuf)\n",
		data_type, g_txn_id, off, pb_len);
	return 0;
}

/*
 * Receive an SSC QMI indication and extract the protobuf payload.
 *
 * Waits for a QMI indication (type=0x04) with msg_id 0x0021 or 0x0022.
 * Extracts TLV 0x02 (data) which contains the SscClientResponse protobuf.
 * Skips QRTR control messages and QMI response messages.
 *
 * Returns protobuf length on success, -1 on error/timeout.
 */
static ssize_t ssc_recv_response(int fd, uint8_t *pb_buf, size_t pb_buf_size)
{
	uint8_t buf[4096];
	struct pollfd pfd = { .fd = fd, .events = POLLIN };

	while (1) {
		int ret = poll(&pfd, 1, SSC_RESPONSE_TIMEOUT_MS);

		if (ret < 0) {
			fprintf(stderr, "ssc-iio-bridge: poll failed: %s\n",
				strerror(errno));
			return -1;
		}
		if (ret == 0) {
			fprintf(stderr,
				"ssc-iio-bridge: SSC response timeout (%d ms)\n",
				SSC_RESPONSE_TIMEOUT_MS);
			return -1;
		}

		struct sockaddr_qrtr src;
		socklen_t src_len = sizeof(src);

		ssize_t n = recvfrom(fd, buf, sizeof(buf), 0,
				     (struct sockaddr *)&src, &src_len);
		if (n < 0) {
			fprintf(stderr, "ssc-iio-bridge: recvfrom failed: %s\n",
				strerror(errno));
			return -1;
		}

		/* Skip QRTR control messages (from name server) */
		if (src.sq_port == QRTR_PORT_CTRL)
			continue;

		/* Need at least QMI header */
		if (n < QMI_HDR_SIZE)
			continue;

		uint8_t msg_type = buf[0];
		uint16_t msg_id = buf[3] | ((uint16_t)buf[4] << 8);
		uint16_t payload_len = buf[5] | ((uint16_t)buf[6] << 8);

		/* Skip QMI responses (type=0x02) — we want indications */
		if (msg_type != QMI_TYPE_INDICATION)
			continue;

		/* Accept both small (0x0021) and large (0x0022) reports */
		if (msg_id != SSC_QMI_MSG_REPORT_SM &&
		    msg_id != SSC_QMI_MSG_REPORT_LG)
			continue;

		fprintf(stdout,
			"ssc-iio-bridge: QMI indication from node %u port %u "
			"msg_id=0x%04x payload=%u bytes\n",
			src.sq_node, src.sq_port, msg_id, payload_len);

		/* Extract TLV 0x02 (protobuf data) from payload */
		const uint8_t *payload = buf + QMI_HDR_SIZE;
		size_t avail = (size_t)(n - QMI_HDR_SIZE);

		if (avail < payload_len)
			payload_len = (uint16_t)avail;

		uint16_t tlv_len;
		const uint8_t *tlv_data = qmi_find_tlv(payload, payload_len,
						       0x02, &tlv_len);
		if (!tlv_data) {
			fprintf(stderr,
				"ssc-iio-bridge: no data TLV (0x02) in indication\n");
			continue;
		}

		if (tlv_len > pb_buf_size) {
			fprintf(stderr,
				"ssc-iio-bridge: protobuf too large (%u > %zu)\n",
				tlv_len, pb_buf_size);
			return -1;
		}

		memcpy(pb_buf, tlv_data, tlv_len);
		return (ssize_t)tlv_len;
	}
}

/* ---------- SUID response parser ---------- */
/*
 * Parse SscClientResponse → SscClientResponseBody → SscSuidResponse.
 *
 * SscClientResponse (ssc-common.proto):
 *   field 1 (SscUid):           source sensor UID
 *   field 2 (repeated Body):    response entries
 *
 * SscClientResponseBody:
 *   field 1 (fixed32): msg_id
 *   field 2 (fixed64): timestamp (DSP 19.2 MHz)
 *   field 3 (bytes):   inner protobuf
 *
 * SscSuidResponse (ssc-sensor-suid.proto):
 *   field 1 (string):       data_type (echoed)
 *   field 2 (repeated Uid): discovered sensor SUIDs
 *
 * SscUid:
 *   field 1 (fixed64): low
 *   field 2 (fixed64): high
 */
static int parse_suid_response(const uint8_t *pb, size_t pb_len,
			       struct ssc_uid *uids, int max_uids,
			       int *n_uids)
{
	int wire_type;
	size_t flen;

	*n_uids = 0;

	/*
	 * Find first SscClientResponse.response (field 2, LEN).
	 * In practice there's usually one response body per indication.
	 */
	size_t resp_off = 0;
	const uint8_t *body = pb_next_field(pb, pb_len, 2, &resp_off,
					    &wire_type, &flen);

	if (!body || wire_type != PB_WIRE_LEN) {
		fprintf(stderr,
			"ssc-iio-bridge: no response body in SscClientResponse\n");
		return -1;
	}

	/* Parse SscClientResponseBody.msg_id (field 1, fixed32) */
	size_t mid_len;
	int mid_wt;
	const uint8_t *mid_p = pb_find_field(body, flen, 1, &mid_wt, &mid_len);

	if (mid_p && mid_wt == PB_WIRE_32BIT) {
		uint32_t msg_id;

		memcpy(&msg_id, mid_p, 4);
		msg_id = le32toh(msg_id);
		fprintf(stdout,
			"ssc-iio-bridge: response body msg_id=%u (0x%x)\n",
			msg_id, msg_id);
		if (msg_id != SSC_MSG_RESPONSE_SUID) {
			fprintf(stderr,
				"ssc-iio-bridge: unexpected msg_id %u "
				"(expected %u for SUID response)\n",
				msg_id, SSC_MSG_RESPONSE_SUID);
			return -1;
		}
	}

	/* Parse SscClientResponseBody.msg (field 3, bytes) = SscSuidResponse */
	size_t inner_len;
	int inner_wt;
	const uint8_t *inner = pb_find_field(body, flen, 3,
					     &inner_wt, &inner_len);

	if (!inner || inner_wt != PB_WIRE_LEN) {
		fprintf(stderr,
			"ssc-iio-bridge: no inner msg in response body\n");
		return -1;
	}

	/* SscSuidResponse.data_type (field 1, string) */
	size_t dt_len;
	int dt_wt;
	const uint8_t *dt = pb_find_field(inner, inner_len, 1,
					  &dt_wt, &dt_len);

	if (dt && dt_wt == PB_WIRE_LEN) {
		fprintf(stdout,
			"ssc-iio-bridge: SUID response data_type='%.*s'\n",
			(int)dt_len, (const char *)dt);
	}

	/* SscSuidResponse.uid (field 2, repeated SscUid) */
	size_t uid_off = 0;

	while (*n_uids < max_uids) {
		size_t uid_msg_len;
		int uid_wt;
		const uint8_t *uid_msg = pb_next_field(inner, inner_len, 2,
						       &uid_off, &uid_wt,
						       &uid_msg_len);
		if (!uid_msg)
			break;
		if (uid_wt != PB_WIRE_LEN)
			continue;

		/* Parse SscUid: field 1 (fixed64 low), field 2 (fixed64 high) */
		size_t low_len, high_len;
		int low_wt, high_wt;
		const uint8_t *low_p = pb_find_field(uid_msg, uid_msg_len,
						     1, &low_wt, &low_len);
		const uint8_t *high_p = pb_find_field(uid_msg, uid_msg_len,
						      2, &high_wt, &high_len);

		if (low_p && high_p &&
		    low_wt == PB_WIRE_64BIT && high_wt == PB_WIRE_64BIT) {
			memcpy(&uids[*n_uids].low, low_p, 8);
			memcpy(&uids[*n_uids].high, high_p, 8);
			fprintf(stdout,
				"ssc-iio-bridge: SUID[%d] = "
				"0x%016llx:0x%016llx\n",
				*n_uids,
				(unsigned long long)uids[*n_uids].high,
				(unsigned long long)uids[*n_uids].low);
			(*n_uids)++;
		}
	}

	fprintf(stdout, "ssc-iio-bridge: found %d sensor SUID(s)\n", *n_uids);
	return 0;
}

/* ---------- Discover mode ---------- */

static int ssc_discover(int fd)
{
	uint32_t ssc_node, ssc_port;
	struct ssc_uid uids[16];
	int n_uids;
	uint8_t pb_buf[4096];
	ssize_t pb_len;

	/* Step 1: Find SSC service via QRTR name server */
	fprintf(stdout,
		"ssc-iio-bridge: looking up SSC service (0x%x) on QRTR bus...\n",
		SSC_QMI_SERVICE_ID);

	if (qrtr_find_ssc(fd, &ssc_node, &ssc_port) < 0)
		return 1;

	/* Step 2: SUID lookup for "accel" */
	fprintf(stdout, "\n--- SUID lookup: accel ---\n");
	if (ssc_send_suid_request(fd, ssc_node, ssc_port, "accel") < 0)
		return 1;

	pb_len = ssc_recv_response(fd, pb_buf, sizeof(pb_buf));
	if (pb_len < 0) {
		fprintf(stderr,
			"ssc-iio-bridge: no response for accel SUID lookup\n");
		return 1;
	}

	if (parse_suid_response(pb_buf, (size_t)pb_len, uids, 16, &n_uids) < 0)
		return 1;

	if (n_uids == 0)
		fprintf(stderr,
			"ssc-iio-bridge: WARNING: no accel sensor SUIDs\n");

	/* Step 3: SUID lookup for "gyro" */
	fprintf(stdout, "\n--- SUID lookup: gyro ---\n");
	if (ssc_send_suid_request(fd, ssc_node, ssc_port, "gyro") < 0)
		return 1;

	pb_len = ssc_recv_response(fd, pb_buf, sizeof(pb_buf));
	if (pb_len < 0) {
		fprintf(stderr,
			"ssc-iio-bridge: no response for gyro SUID lookup\n");
		return 1;
	}

	if (parse_suid_response(pb_buf, (size_t)pb_len, uids, 16, &n_uids) < 0)
		return 1;

	if (n_uids == 0)
		fprintf(stderr,
			"ssc-iio-bridge: WARNING: no gyro sensor SUIDs\n");

	return 0;
}

/* ---------- Main ---------- */

static void usage(const char *progname)
{
	fprintf(stderr, "Usage: %s [--test|--discover]\n", progname);
	fprintf(stderr, "  --test      Open QRTR socket, verify, then exit\n");
	fprintf(stderr, "  --discover  Find SSC service + enumerate accel/gyro SUIDs\n");
}

int main(int argc, char *argv[])
{
	int test_mode = 0, discover_mode = 0;
	int fd, ret;
	uint32_t node = 0, port = 0;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--test") == 0) {
			test_mode = 1;
		} else if (strcmp(argv[i], "--discover") == 0) {
			discover_mode = 1;
		} else if (strcmp(argv[i], "--help") == 0 ||
			   strcmp(argv[i], "-h") == 0) {
			usage(argv[0]);
			return 0;
		} else {
			fprintf(stderr, "ssc-iio-bridge: unknown option: %s\n",
				argv[i]);
			usage(argv[0]);
			return 1;
		}
	}

	fd = qrtr_open(&node, &port);
	if (fd < 0)
		return 1;

	if (test_mode) {
		close(fd);
		fprintf(stdout, "ssc-iio-bridge: test mode OK\n");
		return 0;
	}

	if (discover_mode) {
		ret = ssc_discover(fd);
		close(fd);
		return ret;
	}

	fprintf(stdout, "ssc-iio-bridge: daemon mode not yet implemented\n");
	close(fd);
	return 1;
}
