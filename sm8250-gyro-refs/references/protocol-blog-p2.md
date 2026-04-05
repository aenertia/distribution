Unlocking the Qualcomm Snapdragon Sensor Core

[-EMAINLINE](https://emainline.gitlab.io)

[

Home

](/)

[

About

](/about.html)

[

](/feed.xml)

# Unlocking the Qualcomm Snapdragon Sensor Core

## Part 2: Collecting Information

Yassine Oudjana

Posted on 8th Apr 2022

[Last time](/2021/10/06/Unlocking_SSC_P1.html) we got a step closer to working sensors on mainline Linux by powering on and booting the SLPI successfully. With that easy part out of the way, we can now deal with the hard part: Finding out how to communicate with it and getting something meaningful out of it. Usually when bringing up hardware in the mainline kernel, the downstream kernel drivers, and/or if available, datasheets are used to understand how the hardware works and how to operate it. With it having no open-source drivers nor public documentation however, figuring out how the SSC works will be a challenge on a whole new level.

Without any direct reference material, it would seem to be an impossible task at first, but when looking at it from a different perspective, even the proprietary HAL driver can be used as reference. After all, we know for a fact that it works, so there must be something that can be learned from it.

There are a few ways to understand how the HAL driver works without having its source code on hand. It is possible to disassemble the binary and try to read through assembly code, but getting any meaningful information that way will be quite cumbersome, not to mention the legal uncertainties surrounding this method. A much better alternative in this case would be to run the driver normally, then monitor its interactions with the SSC. After understanding what it does and what for, It should be possible to then imitate it and get identical results from the SSC.

Since it has to talk to hardware, it will have to interact with the kernel using syscalls. Tracing the syscalls it makes will be a good starting point, and for that, the [Linux syscall tracer](https://strace.io/) – usually known as `strace` – is the perfect tool. Using `strace` will allow for monitoring all interactions between the HAL driver and the Linux kernel, and by extension, the SLPI. It can also attach to already running processes, making it easy to collect some data without any preparation, as long as root privileges are available.

## Watching the SSC

The main part of the HAL driver is the sensor service `android.hardware.sensors@1.0-service`, which is started at boot by the init system. Before attaching `strace` to it, its PID has to be found:

```
# pidof android.hardware.sensors@1.0-service
582

```

Then the `-p` argument can be used to attach `strace` to it:

```
# strace -p 582
strace: Process 582 attached
ioctl(3, BINDER_WRITE_READ, 0x7fc7f43d20) = 0

```

Quite underwhelming. Could this be the wrong process? Perhaps the right one can be found using `htop`:

```
PID USER      PRI  NI  VIRT   RES   SHR S CPU% MEM%   TIME+  Command
610 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:01.05 /vendor/bin/hw/android.hardware.sensors@1.0-service
612 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:00.76 /vendor/bin/hw/android.hardware.sensors@1.0-service
613 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:00.76 /vendor/bin/hw/android.hardware.sensors@1.0-service
771 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:35.28 /vendor/bin/hw/android.hardware.sensors@1.0-service
773 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:00.00 /vendor/bin/hw/android.hardware.sensors@1.0-service
774 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:00.70 /vendor/bin/hw/android.hardware.sensors@1.0-service
780 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:00.19 /vendor/bin/hw/android.hardware.sensors@1.0-service
818 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:00.00 /vendor/bin/hw/android.hardware.sensors@1.0-service
819 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:00.67 /vendor/bin/hw/android.hardware.sensors@1.0-service
820 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:00.00 /vendor/bin/hw/android.hardware.sensors@1.0-service
821 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:00.66 /vendor/bin/hw/android.hardware.sensors@1.0-service
827 system     20   0 11.4G  2732  2076 S  0.0  0.1  0:00.00 /vendor/bin/hw/android.hardware.sensors@1.0-service
...

```

There are actually many `android.hardware.sensors@1.0-service` processes, so it appears that the sensor service has multiple threads running. Fortunately, `strace` has a `-f` argument to follow forks, allowing us to attach to all running threads of the sensor service at the same time:

```
# strace -p 582 -f
strace: Process 582 attached with 70 threads
[pid  2475] ppoll([{fd=107, events=POLLIN}, {fd=106, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid  2473] ppoll([{fd=104, events=POLLIN}, {fd=103, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid  1735] ppoll([{fd=101, events=POLLIN}, {fd=100, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid  1734] ppoll([{fd=15, events=POLLIN}, {fd=14, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   982] futex(0x715777ad00, FUTEX_WAIT_BITSET_PRIVATE, 747816, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   980] futex(0x71576f55e8, FUTEX_WAIT_BITSET_PRIVATE, 1219316, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   977] ppoll([{fd=98, events=POLLIN}, {fd=97, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   973] ppoll([{fd=95, events=POLLIN}, {fd=94, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   972] futex(0x72078ff150, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   976] rt_sigtimedwait([RTMIN],  <unfinished ...>
[pid   975] futex(0x72078ff610, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   970] ppoll([{fd=92, events=POLLIN}, {fd=91, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   969] futex(0x72078ff650, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   966] futex(0x72078fd790, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   967] ppoll([{fd=89, events=POLLIN}, {fd=88, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   963] ppoll([{fd=86, events=POLLIN}, {fd=85, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   962] futex(0x72078fd550, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   958] futex(0x72078fdf90, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   959] ppoll([{fd=83, events=POLLIN}, {fd=82, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   954] ppoll([{fd=80, events=POLLIN}, {fd=79, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   953] futex(0x72078ff310, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   948] ppoll([{fd=77, events=POLLIN}, {fd=76, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   947] futex(0x72078ff710, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   939] ppoll([{fd=71, events=POLLIN}, {fd=70, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   944] ppoll([{fd=74, events=POLLIN}, {fd=73, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   943] futex(0x72078fec10, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   942] futex(0x72078ff010, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   938] futex(0x72078ff090, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   933] ppoll([{fd=68, events=POLLIN}, {fd=67, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   932] futex(0x72078ff1d0, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   927] ppoll([{fd=65, events=POLLIN}, {fd=64, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   921] ppoll([{fd=62, events=POLLIN}, {fd=61, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   926] futex(0x72078fed50, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   920] futex(0x72078fec90, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   916] ppoll([{fd=56, events=POLLIN}, {fd=55, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   917] futex(0x72078fe150, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   918] ppoll([{fd=59, events=POLLIN}, {fd=58, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   915] futex(0x72078fe790, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   913] ppoll([{fd=53, events=POLLIN}, {fd=52, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   912] futex(0x72078fe350, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   903] ppoll([{fd=50, events=POLLIN}, {fd=49, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   902] futex(0x72078fe010, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   895] ppoll([{fd=47, events=POLLIN}, {fd=46, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   894] futex(0x72078fe8d0, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   885] ppoll([{fd=44, events=POLLIN}, {fd=43, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   884] futex(0x72078febd0, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   876] ppoll([{fd=41, events=POLLIN}, {fd=40, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   875] futex(0x72078fea90, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   854] ppoll([{fd=35, events=POLLIN}, {fd=34, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   857] futex(0x72078feb90, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   853] futex(0x72078fdfd0, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   858] ppoll([{fd=38, events=POLLIN}, {fd=37, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   846] ppoll([{fd=32, events=POLLIN}, {fd=31, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   845] futex(0x72078fe410, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   832] futex(0x72078fe290, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   828] ppoll([{fd=26, events=POLLIN}, {fd=25, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   833] ppoll([{fd=29, events=POLLIN}, {fd=28, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   827] futex(0x72078fe250, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   821] ppoll([{fd=23, events=POLLIN}, {fd=22, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   820] futex(0x72078fe0d0, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   819] ppoll([{fd=20, events=POLLIN}, {fd=19, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   780] futex(0x72078fd410, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   774] ppoll([{fd=12, events=POLLIN}, {fd=11, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   773] futex(0x72078fd8d0, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   771] futex(0x72078fd4d0, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid   613] ppoll([{fd=8, events=POLLIN}, {fd=7, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   612] read(6,  <unfinished ...>
[pid   610] pselect6(6, [5], NULL, [5], NULL, NULL <unfinished ...>
[pid   582] ioctl(3, BINDER_WRITE_READ <unfinished ...>
[pid   818] futex(0x72078fe210, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid  1734] <... ppoll resumed> )       = 1 ([{fd=14, revents=POLLIN}])
[pid  1734] recvfrom(14, "\4\226\5\3\0$\0\1\4\0\275\23zo\2\10\0\331\0\200R\203`\336\26\3\4\0\0\0\0\0"..., 56, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\0\0\2\0\0\0\1\0\0\0)\0\0\0\0\0\0\0"}, [20]) = 43
[pid  1734] rt_sigprocmask(0x539a1968 /* SIG_??? */, NULL, [USR2 RTMIN], 8) = 0
[pid  1734] rt_sigprocmask(0x539a1958 /* SIG_??? */, NULL, [USR2 RTMIN], 8) = 0
[pid  1734] futex(0x72078fd410, FUTEX_WAKE_PRIVATE, 2147483647) = 1
[pid   780] <... futex resumed> )       = 0
[pid  1734] ppoll([{fd=15, events=POLLIN}, {fd=14, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   780] futex(0x72078fd410, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid  1734] <... ppoll resumed> )       = 1 ([{fd=14, revents=POLLIN}])
[pid  1734] recvfrom(14, "\4\227\5\3\0$\0\1\4\0\23\24\177o\2\10\0\263\217\263\246\205`\336\26\3\4\0\0\0\0\0"..., 56, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\0\0\2\0\0\0\1\0\0\0)\0\0\0\0\0\0\0"}, [20]) = 43
[pid  1734] rt_sigprocmask(0x539a1968 /* SIG_??? */, NULL, [USR2 RTMIN], 8) = 0
[pid  1734] rt_sigprocmask(0x539a1958 /* SIG_??? */, NULL, [USR2 RTMIN], 8) = 0
[pid  1734] futex(0x72078fd410, FUTEX_WAKE_PRIVATE, 2147483647) = 1
[pid  1734] ppoll([{fd=15, events=POLLIN}, {fd=14, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   780] <... futex resumed> )       = 0
[pid   780] futex(0x72078fd410, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid  1734] <... ppoll resumed> )       = 1 ([{fd=14, revents=POLLIN}])
[pid  1734] recvfrom(14, "\4\230\5\3\0$\0\1\4\0o\24\204o\2\10\0\22\216\352\372\207`\336\26\3\4\0\0\0\0\0"..., 56, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\0\0\2\0\0\0\1\0\0\0)\0\0\0\0\0\0\0"}, [20]) = 43
[pid  1734] rt_sigprocmask(0x539a1968 /* SIG_??? */, NULL, [USR2 RTMIN], 8) = 0
[pid  1734] rt_sigprocmask(0x539a1958 /* SIG_??? */, NULL, [USR2 RTMIN], 8) = 0
[pid  1734] futex(0x72078fd410, FUTEX_WAKE_PRIVATE, 2147483647) = 1
[pid   780] <... futex resumed> )       = 0
[pid  1734] ppoll([{fd=15, events=POLLIN}, {fd=14, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   780] futex(0x72078fd410, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid  1734] <... ppoll resumed> )       = 1 ([{fd=14, revents=POLLIN}])
[pid  1734] recvfrom(14, "\4\231\5\3\0$\0\1\4\0\374\24\211o\2\10\0 \3357O\212`\336\26\3\4\0\0\0\0\0"..., 56, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\0\0\2\0\0\0\1\0\0\0)\0\0\0\0\0\0\0"}, [20]) = 43
[pid  1734] rt_sigprocmask(0x539a1968 /* SIG_??? */, NULL, [USR2 RTMIN], 8) = 0
[pid  1734] rt_sigprocmask(0x539a1958 /* SIG_??? */, NULL, [USR2 RTMIN], 8) = 0
[pid  1734] futex(0x72078fd410, FUTEX_WAKE_PRIVATE, 2147483647) = 1
[pid  1734] ppoll([{fd=15, events=POLLIN}, {fd=14, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   780] <... futex resumed> )       = 0
[pid   780] futex(0x72078fd410, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid  1734] <... ppoll resumed> )       = 1 ([{fd=14, revents=POLLIN}])
[pid  1734] recvfrom(14, "\4\235\5\3\0$\0\1\4\0-\26\235o\2\10\0\5\224\365\237\223`\336\26\3\4\0\0\0\0\0"..., 56, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\0\0\2\0\0\0\1\0\0\0)\0\0\0\0\0\0\0"}, [20]) = 43
[pid  1734] rt_sigprocmask(0x539a1968 /* SIG_??? */, NULL, [USR2 RTMIN], 8) = 0
[pid  1734] rt_sigprocmask(0x539a1958 /* SIG_??? */, NULL, [USR2 RTMIN], 8) = 0
[pid  1734] futex(0x72078fd410, FUTEX_WAKE_PRIVATE, 2147483647) = 1
[pid  1734] ppoll([{fd=15, events=POLLIN}, {fd=14, events=POLLIN}], 2, NULL, NULL, 0 <unfinished ...>
[pid   780] <... futex resumed> )       = 0
[pid   780] futex(0x72078fd410, FUTEX_WAIT_BITSET_PRIVATE, 4294967294, NULL, FUTEX_BITSET_MATCH_ANY

```

Now that is more like it. There is a lot going on, so filtering the syscalls would be a good idea. Since we are looking for data transferred between SSC and the sensor service, we can focus on `sendto` and `recvfrom` calls. This can be done using the `-e` argument. The `-xx` argument is also added to print all strings in hexadecimal format, and `-s 1024` to increase the string size limit so that no characters get truncated:

```
# strace -p 582 -f -e trace=sendto,recvfrom -xx -s 1024
strace: Process 582 attached with 70 threads

```

Nothing?

This is being done with the screen off, so the silence might be due to the sensors being suspended to save power. One sensor should be active however; as the phone can be woken up by waving a hand in front of the proximity sensor. To confirm, the proximity sensor is covered then uncovered a few times:

```
[pid   977] recvfrom(97, "\x04\xad\x00\x05\x00\x1a\x00\x01\x01\x00\x1a\x02\x04\x00\xf2\xfe\xf4\x71\x03\x0c\x00\x00\x00\x01\x00\xa0\x3a\x29\xb2\x00\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 33
[pid   977] recvfrom(97, "\x04\xae\x00\x05\x00\x1a\x00\x01\x01\x00\x1a\x02\x04\x00\x09\x26\xf5\x71\x03\x0c\x00\x00\x00\x00\x00\xa0\x3a\x29\xb2\x00\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 33
[pid   582] sendto(14, "\x00\xc0\x01\x02\x00\x04\x00\x10\x01\x00\x01", 11, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x01\x00\x00\x00\x29\x00\x00\x00\xd8\x33\xf4\xc7"}, 20) = 11
[pid  1734] recvfrom(14, "\x02\xc0\x01\x02\x00\x29\x00\x02\x02\x00\x00\x00\x10\x04\x00\xe0\x2d\xf5\x71\x11\x08\x00\xfb\xcb\x93\x10\xab\x61\xde\x16\x13\x04\x00\x00\x00\x00\x00\x14\x08\x00\xa9\x13\x2e\xdc\x0e\x35\x00\x00", 56, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x01\x00\x00\x00\x29\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 48
[pid   582] sendto(94, "\x00\x7e\x00\x02\x00\x26\x00\x01\x01\x00\x28\x02\x01\x00\x00\x03\x04\x00\x00\x00\x05\x00\x04\x0c\x00\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x11\x05\x00\x00\x00\x00\x00\x01", 45, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x58\x34\xf4\xc7"}, 20) = 45
[pid   973] recvfrom(94, "\x04\x3f\x00\x05\x00\x1a\x00\x01\x01\x00\x1f\x02\x04\x00\x09\x26\xf5\x71\x03\x0c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 33
[pid   973] recvfrom(94, "\x02\x7e\x00\x02\x00\x09\x00\x02\x02\x00\x00\x00\x10\x01\x00\x1f", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 16
[pid  1734] recvfrom(14, "\x04\x15\x06\x03\x00\x24\x00\x01\x04\x00\x62\x3a\xf5\x71\x02\x08\x00\xa6\xa0\x66\x16\xab\x61\xde\x16\x03\x04\x00\x00\x00\x00\x00\x10\x08\x00\x0a\xe3\x00\xe2\x0e\x35\x00\x00", 56, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x01\x00\x00\x00\x29\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 43
[pid   982] sendto(94, "\x00\x7f\x00\x00\x00\x00\x00", 7, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\xb8\xf0\xa9\x53"}, 20) = 7
[pid   973] recvfrom(94, "\x02\x7f\x00\x00\x00\x05\x00\x02\x02\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 12
[pid   977] recvfrom(97, "\x04\xaf\x00\x05\x00\x1a\x00\x01\x01\x00\x1a\x02\x04\x00\x69\x8f\xf5\x71\x03\x0c\x00\x00\x00\x01\x00\xa0\x3a\x29\xb2\x00\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 33
[pid   977] recvfrom(97, "\x04\xb0\x00\x05\x00\x1a\x00\x01\x01\x00\x1a\x02\x04\x00\xce\xa3\xf5\x71\x03\x0c\x00\x00\x00\x00\x00\xa0\x3a\x29\xb2\x00\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 33
[pid   977] recvfrom(97, "\x04\xb1\x00\x05\x00\x1a\x00\x01\x01\x00\x1a\x02\x04\x00\x94\x10\xf6\x71\x03\x0c\x00\x00\x00\x01\x00\xa0\x3a\x29\xb2\x00\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 33
[pid   977] recvfrom(97, "\x04\xb2\x00\x05\x00\x1a\x00\x01\x01\x00\x1a\x02\x04\x00\x13\x19\xf6\x71\x03\x0c\x00\x00\x00\x00\x00\xa0\x3a\x29\xb2\x00\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 33
[pid   977] recvfrom(97, "\x04\xb3\x00\x05\x00\x1a\x00\x01\x01\x00\x1a\x02\x04\x00\xdf\x1f\xf6\x71\x03\x0c\x00\x00\x00\x01\x00\xa0\x3a\x29\xb2\x00\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 33
[pid   977] recvfrom(97, "\x04\xb4\x00\x05\x00\x1a\x00\x01\x01\x00\x1a\x02\x04\x00\x5f\x28\xf6\x71\x03\x0c\x00\x00\x00\x00\x00\xa0\x3a\x29\xb2\x00\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 33

```

And sure enough, data starts coming in. A `recvfrom` call is traced each time the proximity sensor is covered or uncovered. There are a few extra `sendto` and `recvfrom` calls after the first time the sensor is covered, so it seems that something happens when the screen turns on. That will not be important now though.

## Reading the data

Right now all we have is a bunch of `strace` output lines with traced syscalls and the arguments passed through them. Since we are after raw data, some work has to be done on those lines.
To start analyzing the data format, a single `recvfrom` is taken:

```
[pid   977] recvfrom(97, "\x04\xb1\x00\x05\x00\x1a\x00\x01\x01\x00\x1a\x02\x04\x00\x94\x10\xf6\x71\x03\x0c\x00\x00\x00\x01\x00\xa0\x3a\x29\xb2\x00\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 33

```

Then the data, which is [the second argument of `recvfrom`](https://linux.die.net/man/2/recvfrom), is extracted and formatted nicely:

```
# printf "\x04\xb1\x00\x05\x00\x1a\x00\x01\x01\x00\x1a\x02\x04\x00\x94\x10\xf6\x71\x03\x0c\x00\x00\x00\x01\x00\xa0\x3a\x29\xb2\x00\x00\x00\x00" | xxd -g 1
00000000: 04 b1 00 05 00 1a 00 01 01 00 1a 02 04 00 94 10  ................
00000010: f6 71 03 0c 00 00 00 01 00 a0 3a 29 b2 00 00 00  .q........:)....
00000020: 00                                               .

```

These are the bytes received, put in a single line:

```
04 b1 00 05 00 1a 00 01 01 00 1a 02 04 00 94 10 f6 71 03 0c 00 00 00 01 00 a0 3a 29 b2 00 00 00 00

```

There is a prominent pattern that can be quickly identified here: There are several non-zero bytes followed by zeroes, such as  `b1 00`, `05 00`, `1a 00`, and `0c 00 00 00`. This is a strong indicator that this data is little-endian, meaning that integers that are 2 bytes or longer are represented in such a way that their least significant byte comes first, followed by the second least significant byte, and so on.

To interpret the data, it might help to start off with some guesses on the fields it is composed of. At a first glance, it looks like it can be split into these fields, resembled with a C struct:

```
struct prox_pkt {
u8 var1;	// 04
u16 var2;	// b1 00
u16 var3;	// 05 00
u16 var4;	// 1a 00
u8 var5;	// 01
u16 var6;	// 01 00
u8 var7;	// 1a
u8 var8;	// 02
u16 var9;	// 04 00
u8 var10;	// 94
u8 var11;	// 10
u8 var12;	// f6
u8 var13;	// 71
u8 var14;	// 03
u32 var15;	// 0c 00 00 00
u16 var16;	// 01 00
u8 var17;	// a0
u8 var18;	// 3a
u8 var19;	// 29
u8 var20;	// b2
u32 var21;	// 00 00 00 00
};

struct prox_pkt pkt1 = {0x04, 0xb1, 0x05, 0x1a, 0x01, 0x01, 0x1a, 0x02, 0x04, 0x94, 0x10, 0xf6, 0x71, 0x03, 0x0c, 0x01, 0xa0, 0x3a, 0x29, 0xb2, 0x00};

```

Again, the little-endianness of the data is clearly seen in every `u16` and `u32` field, which are 2 bytes and 4 bytes long respectively. The zeroes helped with identifying the sizes of those fields. There might be additional 2 or 4 byte long fields that are holding large integers where their most significant bytes are non-zero, making them difficult to identify at this stage.

Next, the data is analyzed further by comparing 2 consecutive lines. The steps above are repeated with the next line:

```
[pid   977] recvfrom(97, "\x04\xb2\x00\x05\x00\x1a\x00\x01\x01\x00\x1a\x02\x04\x00\x13\x19\xf6\x71\x03\x0c\x00\x00\x00\x00\x00\xa0\x3a\x29\xb2\x00\x00\x00\x00", 820, MSG_DONTWAIT, {sa_family=AF_IB, sa_data="\x00\x00\x02\x00\x00\x00\x09\x00\x00\x00\x3f\x00\x00\x00\x00\x00\x00\x00"}, [20]) = 33

```

```
04 b2 00 05 00 1a 00 01 01 00 1a 02 04 00 13 19 f6 71 03 0c 00 00 00 00 00 a0 3a 29 b2 00 00 00 00

```

The format seems identical, so it should be possible to compare this with the previous line directly.

```
struct prox_pkt pkt1 = {0x04, 0xb1, 0x05, 0x1a, 0x01, 0x01, 0x1a, 0x02, 0x04, 0x94, 0x10, 0xf6, 0x71, 0x03, 0x0c, 0x01, 0xa0, 0x3a, 0x29, 0xb2, 0x00};
struct prox_pkt pkt2 = {0x04, 0xb2, 0x05, 0x1a, 0x01, 0x01, 0x1a, 0x02, 0x04, 0x13, 0x19, 0xf6, 0x71, 0x03, 0x0c, 0x00, 0xa0, 0x3a, 0x29, 0xb2, 0x00};

```

Most of the values remained constant. The only values that changed are `var2` which increased by 1, `var10` and `var11` which changed somewhat significantly, and `var16` which changed from 1 to 0.

Looking at a larger set of lines should make it possible to identify patterns and find constant values with more certainty, as well as find some of the hiding large integers mentioned earlier.

Formatting each line from the `strace` output manually will take a lot of time. With some quick Python magic though:

```
import sys
import re

i = open(sys.argv[1], "r")

ilines = i.readlines()

for iline in ilines:
if "ENOMSG" in iline:
continue
if "sendto" not in iline and "recvfrom" not in iline:
continue

line = ""
line += re.findall("\d+", iline)[0] + "\t"

if "sendto" in iline:
line += "send"
elif "recvfrom" in iline:
line += "recv"
line += "\t"

fd = re.findall("\(\d\d", iline)
if len(fd) == 0:
continue

line += fd[0][1::] + "\t"

rawdata = re.findall("[^\"][x][0-9a-f][0-9a-f][^\"]+", iline)
if len(rawdata) == 0:
continue
rawdata = rawdata[0][2::].split("\\x")

data = []

for rawbyte in rawdata:
data.append(int(rawbyte, 16))

line += "|"
for byte in data:
line += chr(byte) if byte <= 127 and byte >= 32 else "."
line += "|\t\t"
for byte in data:
line += "{:02x}".format(byte) + " "

print(line)

i.close()

```

The `strace` output can be quickly converted into a nice and easy to read format, including an ASCII representation that should reveal any text possibly carried in the packets:

```
977	recv	97	|.................q........:).....|		04 ad 00 05 00 1a 00 01 01 00 1a 02 04 00 f2 fe f4 71 03 0c 00 00 00 01 00 a0 3a 29 b2 00 00 00 00
977	recv	97	|...............&.q........:).....|		04 ae 00 05 00 1a 00 01 01 00 1a 02 04 00 09 26 f5 71 03 0c 00 00 00 00 00 a0 3a 29 b2 00 00 00 00
582	send	14	|...........|		00 c0 01 02 00 04 00 10 01 00 01
1734	recv	14	|.....)..........-.q........a.................5..|		02 c0 01 02 00 29 00 02 02 00 00 00 10 04 00 e0 2d f5 71 11 08 00 fb cb 93 10 ab 61 de 16 13 04 00 00 00 00 00 14 08 00 a9 13 2e dc 0e 35 00 00
582	send	94	|.~...&....(..................................|		00 7e 00 02 00 26 00 01 01 00 28 02 01 00 00 03 04 00 00 00 05 00 04 0c 00 ff ff 00 00 00 00 00 00 00 00 00 00 11 05 00 00 00 00 00 01
973	recv	94	|.?.............&.q...............|		04 3f 00 05 00 1a 00 01 01 00 1f 02 04 00 09 26 f5 71 03 0c 00 00 00 00 00 00 00 00 00 00 00 00 00
973	recv	94	|.~..............|		02 7e 00 02 00 09 00 02 02 00 00 00 10 01 00 1f
1734	recv	14	|.....$....b:.q.....f..a.................5..|		04 15 06 03 00 24 00 01 04 00 62 3a f5 71 02 08 00 a6 a0 66 16 ab 61 de 16 03 04 00 00 00 00 00 10 08 00 0a e3 00 e2 0e 35 00 00
982	send	94	|......|		00 7f 00 00 00 00 00
973	recv	94	|...........|		02 7f 00 00 00 05 00 02 02 00 00 00
977	recv	97	|..............i..q........:).....|		04 af 00 05 00 1a 00 01 01 00 1a 02 04 00 69 8f f5 71 03 0c 00 00 00 01 00 a0 3a 29 b2 00 00 00 00
977	recv	97	|.................q........:).....|		04 b0 00 05 00 1a 00 01 01 00 1a 02 04 00 ce a3 f5 71 03 0c 00 00 00 00 00 a0 3a 29 b2 00 00 00 00
977	recv	97	|.................q........:).....|		04 b1 00 05 00 1a 00 01 01 00 1a 02 04 00 94 10 f6 71 03 0c 00 00 00 01 00 a0 3a 29 b2 00 00 00 00
977	recv	97	|.................q........:).....|		04 b2 00 05 00 1a 00 01 01 00 1a 02 04 00 13 19 f6 71 03 0c 00 00 00 00 00 a0 3a 29 b2 00 00 00 00
977	recv	97	|.................q........:).....|		04 b3 00 05 00 1a 00 01 01 00 1a 02 04 00 df 1f f6 71 03 0c 00 00 00 01 00 a0 3a 29 b2 00 00 00 00
977	recv	97	|.............._(.q........:).....|		04 b4 00 05 00 1a 00 01 01 00 1a 02 04 00 5f 28 f6 71 03 0c 00 00 00 00 00 a0 3a 29 b2 00 00 00 00

```

Columns from left to right: PID, direction (send/receive), socket file descriptor, ASCII representation, bytes in hexadecimal.

Looking at the last six packets, some interesting patterns are found:

The second byte in each packet (`var2`) is incremented by 1 on each packet. It might be some sort of a counter.
Bytes 14, 15 and 16 seem to be part of a single variable that is always increasing. Along with byte 17, they likely make up an unsigned 32-bit timestamp, as knowing the time when a sensor reading was taken is needed for calculating relative changes among other things, and there are no other bytes that might represent time here.
The 24th Byte alternates between 1 and 0. This makes it almost certainly a boolean carrying the proximity sensor data, as it exactly matches the covering/uncovering of the sensor.

Another pattern can be found by taking a look at all the packets including the ones in the first `sendto`/`recvfrom` syscalls:

The first byte is always 0 when a packet is sent, and either 2 or 4 when it is received. This might be a header with some specific meaning for each of those three values.

The other values remain constant, so it will not be possible to understand their purpose without some external reference or context that would give them meaning.

With the new findings, an updated `struct prox_pkt` would look like this:

```
struct prox_pkt {
u8 header;
u16 counter;
u16 var3;
u16 var4;
u8 var5;
u16 var6;
u8 var7;
u8 var8;
u16 var9;
u32 timestamp;
u8 var11;
u32 var12;
bool sensor_val;
u8 var14;
u8 var15;
u8 var16;
u8 var17;
u8 var18;
u32 var19;
};

```

Some important fields have been identified so far, but the purpose of most still remains unknown.

The next step would be to identify the format of this packet, and for that, there are a couple of clues. First of all, the packets traced are moving to and from a Hexagon DSP on a
