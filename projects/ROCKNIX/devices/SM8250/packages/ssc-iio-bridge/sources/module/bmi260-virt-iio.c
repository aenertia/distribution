// SPDX-License-Identifier: GPL-2.0
/*
 * bmi260-virt-iio: Virtual IIO device for ssc-iio-bridge
 *
 * Creates a platform IIO device named "bmi260" with 6 channels:
 *   in_accel_x/y/z  (IIO_ACCEL)
 *   in_anglvel_x/y/z (IIO_ANGL_VEL)
 *
 * The daemon writes raw integer values via sysfs write_raw;
 * InputPlumber reads them via libiio's sysfs polling.
 *
 * Scale = 0.001 (raw stored as int = SI_value * 1000).
 * Offset = 0.
 *
 * Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/iio/iio.h>
#include <linux/spinlock.h>

#define DRIVER_NAME	"bmi260-virt"
#define DEVICE_NAME	"bmi260"
#define NUM_CHANNELS	6

/* Channel indices — must match iio_chan_spec order */
enum {
	CH_ACCEL_X = 0,
	CH_ACCEL_Y,
	CH_ACCEL_Z,
	CH_GYRO_X,
	CH_GYRO_Y,
	CH_GYRO_Z,
};

struct bmi260_virt_state {
	spinlock_t lock;
	s32 raw[NUM_CHANNELS];
};

#define BMI260_ACCEL_CHANNEL(axis, addr) {		\
	.type = IIO_ACCEL,				\
	.modified = 1,					\
	.channel2 = IIO_MOD_##axis,			\
	.address = (addr),				\
	.info_mask_separate = BIT(IIO_CHAN_INFO_RAW),	\
	.info_mask_shared_by_type = BIT(IIO_CHAN_INFO_SCALE) | \
				    BIT(IIO_CHAN_INFO_OFFSET), \
}

#define BMI260_GYRO_CHANNEL(axis, addr) {		\
	.type = IIO_ANGL_VEL,				\
	.modified = 1,					\
	.channel2 = IIO_MOD_##axis,			\
	.address = (addr),				\
	.info_mask_separate = BIT(IIO_CHAN_INFO_RAW),	\
	.info_mask_shared_by_type = BIT(IIO_CHAN_INFO_SCALE) | \
				    BIT(IIO_CHAN_INFO_OFFSET), \
}

static const struct iio_chan_spec bmi260_virt_channels[] = {
	BMI260_ACCEL_CHANNEL(X, CH_ACCEL_X),
	BMI260_ACCEL_CHANNEL(Y, CH_ACCEL_Y),
	BMI260_ACCEL_CHANNEL(Z, CH_ACCEL_Z),
	BMI260_GYRO_CHANNEL(X, CH_GYRO_X),
	BMI260_GYRO_CHANNEL(Y, CH_GYRO_Y),
	BMI260_GYRO_CHANNEL(Z, CH_GYRO_Z),
};

static int bmi260_virt_read_raw(struct iio_dev *indio_dev,
				struct iio_chan_spec const *chan,
				int *val, int *val2, long mask)
{
	struct bmi260_virt_state *st = iio_priv(indio_dev);

	switch (mask) {
	case IIO_CHAN_INFO_RAW:
		spin_lock(&st->lock);
		*val = st->raw[chan->address];
		spin_unlock(&st->lock);
		return IIO_VAL_INT;

	case IIO_CHAN_INFO_SCALE:
		/* 0.001 = 1/1000: IIO_VAL_FRACTIONAL with val=1, val2=1000 */
		*val = 1;
		*val2 = 1000;
		return IIO_VAL_FRACTIONAL;

	case IIO_CHAN_INFO_OFFSET:
		*val = 0;
		return IIO_VAL_INT;
	}

	return -EINVAL;
}

static int bmi260_virt_write_raw(struct iio_dev *indio_dev,
				 struct iio_chan_spec const *chan,
				 int val, int val2, long mask)
{
	struct bmi260_virt_state *st = iio_priv(indio_dev);

	if (mask != IIO_CHAN_INFO_RAW)
		return -EINVAL;

	spin_lock(&st->lock);
	st->raw[chan->address] = val;
	spin_unlock(&st->lock);

	return 0;
}

static const struct iio_info bmi260_virt_info = {
	.read_raw = bmi260_virt_read_raw,
	.write_raw = bmi260_virt_write_raw,
};

static struct platform_device *bmi260_pdev;

static int bmi260_virt_probe(struct platform_device *pdev)
{
	struct iio_dev *indio_dev;
	struct bmi260_virt_state *st;

	indio_dev = devm_iio_device_alloc(&pdev->dev, sizeof(*st));
	if (!indio_dev)
		return -ENOMEM;

	st = iio_priv(indio_dev);
	spin_lock_init(&st->lock);
	memset(st->raw, 0, sizeof(st->raw));

	indio_dev->name = DEVICE_NAME;
	indio_dev->info = &bmi260_virt_info;
	indio_dev->modes = INDIO_DIRECT_MODE;
	indio_dev->channels = bmi260_virt_channels;
	indio_dev->num_channels = ARRAY_SIZE(bmi260_virt_channels);

	platform_set_drvdata(pdev, indio_dev);

	return devm_iio_device_register(&pdev->dev, indio_dev);
}

static struct platform_driver bmi260_virt_driver = {
	.probe = bmi260_virt_probe,
	.driver = {
		.name = DRIVER_NAME,
	},
};

static int __init bmi260_virt_init(void)
{
	int ret;

	ret = platform_driver_register(&bmi260_virt_driver);
	if (ret)
		return ret;

	bmi260_pdev = platform_device_register_simple(DRIVER_NAME, -1,
						      NULL, 0);
	if (IS_ERR(bmi260_pdev)) {
		ret = PTR_ERR(bmi260_pdev);
		platform_driver_unregister(&bmi260_virt_driver);
		return ret;
	}

	return 0;
}

static void __exit bmi260_virt_exit(void)
{
	platform_device_unregister(bmi260_pdev);
	platform_driver_unregister(&bmi260_virt_driver);
}

module_init(bmi260_virt_init);
module_exit(bmi260_virt_exit);

MODULE_AUTHOR("ROCKNIX");
MODULE_DESCRIPTION("Virtual IIO device for ssc-iio-bridge SSC sensor data");
MODULE_LICENSE("GPL v2");
