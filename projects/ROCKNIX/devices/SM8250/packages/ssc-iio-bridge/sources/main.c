// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)
//
// ssc-iio-bridge: Qualcomm SLPI sensor to Linux IIO device bridge
// AP <-- QRTR/QMI --> SLPI DSP,  AP <-- IIO configfs --> /dev/iio:deviceN

#include <sys/socket.h>
#include <linux/qrtr.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#define SSC_QMI_SERVICE_ID  0x190
#define SSC_QMI_VERSION     1

static void usage(const char *progname)
{
	fprintf(stderr, "Usage: %s [--test]\n", progname);
	fprintf(stderr, "  --test   Open QRTR socket, verify, then exit\n");
}

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

int main(int argc, char *argv[])
{
	int test_mode = 0;
	int fd;
	uint32_t node = 0, port = 0;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--test") == 0) {
			test_mode = 1;
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

	fprintf(stdout, "ssc-iio-bridge: daemon mode not yet implemented\n");
	close(fd);
	return 1;
}
