#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define HELPER_AAR 0x2323
#define HELPER_CPU 3
#define HELPER_DELAY_SECONDS 5

/* Direct symbol addresses from the fixed baseline vmlinux. */
#define PANIC_CPU_ADDRESS UINT64_C(0xffff80008223fa08)
#define KASAN_FLAGS_ADDRESS UINT64_C(0xffff8000827b8980)

struct vuln_req {
	unsigned long idx;
	unsigned long alloc_len;
	void *user_buf;
	size_t user_buf_len;
	unsigned long address;
	unsigned long value;
	char is_oob_write;
	char is_logged;
};

struct helper_buffers {
	struct vuln_req panic_req;
	struct vuln_req kasan_req;
	uint64_t panic_value;
	uint64_t kasan_value;
	char result[256];
};

static struct helper_buffers buffers;

_Static_assert(sizeof(struct vuln_req) == 56,
	       "vuln_req ABI does not match the kernel module");

static uint64_t elapsed_milliseconds(struct timespec start, struct timespec end)
{
	int64_t seconds = end.tv_sec - start.tv_sec;
	int64_t nanoseconds = end.tv_nsec - start.tv_nsec;

	if (nanoseconds < 0) {
		seconds--;
		nanoseconds += 1000000000;
	}
	return (uint64_t)(seconds * 1000 + nanoseconds / 1000000);
}

int main(int argc, char **argv)
{
	struct timespec start;
	struct timespec deadline;
	struct timespec end;
	cpu_set_t cpu_set;
	uint64_t elapsed_ms;
	int device_fd;
	int result_fd;
	int panic_rc;
	int kasan_rc;
	int sleep_rc;
	int result_length;
	ssize_t written;

	if (argc != 2) {
		fprintf(stderr, "usage: %s RESULT_FILE\n", argv[0]);
		return 1;
	}

	CPU_ZERO(&cpu_set);
	CPU_SET(HELPER_CPU, &cpu_set);
	if (sched_setaffinity(0, sizeof(cpu_set), &cpu_set) < 0) {
		perror("sched_setaffinity");
		return 1;
	}

	device_fd = open("/dev/vuln", O_RDWR | O_CLOEXEC);
	if (device_fd < 0) {
		perror("open /dev/vuln");
		return 1;
	}

	result_fd = open(argv[1], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0644);
	if (result_fd < 0) {
		perror("open result file");
		close(device_fd);
		return 1;
	}

	if (mlock(&buffers, sizeof(buffers)) < 0) {
		perror("mlock");
		close(result_fd);
		close(device_fd);
		return 1;
	}
	memset(&buffers, 0, sizeof(buffers));

	buffers.panic_req.user_buf = &buffers.panic_value;
	buffers.panic_req.user_buf_len = sizeof(buffers.panic_value);
	buffers.panic_req.address = (unsigned long)PANIC_CPU_ADDRESS;
	buffers.kasan_req.user_buf = &buffers.kasan_value;
	buffers.kasan_req.user_buf_len = sizeof(buffers.kasan_value);
	buffers.kasan_req.address = (unsigned long)KASAN_FLAGS_ADDRESS;

	if (write(STDOUT_FILENO, "READY\n", 6) != 6) {
		perror("write READY");
		return 1;
	}

	if (clock_gettime(CLOCK_MONOTONIC, &start) < 0) {
		perror("clock_gettime");
		return 1;
	}
	deadline = start;
	deadline.tv_sec += HELPER_DELAY_SECONDS;

	do {
		sleep_rc = clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME,
					   &deadline, NULL);
	} while (sleep_rc == EINTR);
	if (sleep_rc != 0) {
		fprintf(stderr, "clock_nanosleep: %s\n", strerror(sleep_rc));
		return 1;
	}

	panic_rc = ioctl(device_fd, HELPER_AAR, &buffers.panic_req);
	kasan_rc = ioctl(device_fd, HELPER_AAR, &buffers.kasan_req);

	if (clock_gettime(CLOCK_MONOTONIC, &end) < 0) {
		perror("clock_gettime");
		return 1;
	}
	elapsed_ms = elapsed_milliseconds(start, end);

	result_length = snprintf(buffers.result, sizeof(buffers.result),
				 "elapsed_ms=%" PRIu64 "\n"
				 "panic_cpu_rc=%d\n"
				 "panic_cpu=0x%08" PRIx32 "\n"
				 "kasan_flags_rc=%d\n"
				 "kasan_flags=0x%016" PRIx64 "\n",
				 elapsed_ms, panic_rc, (uint32_t)buffers.panic_value,
				 kasan_rc, buffers.kasan_value);
	if (result_length < 0 || (size_t)result_length >= sizeof(buffers.result)) {
		fprintf(stderr, "format result failed\n");
		return 1;
	}

	written = write(result_fd, buffers.result, (size_t)result_length);
	if (written != result_length) {
		perror("write result");
		return 1;
	}
	if (fsync(result_fd) < 0) {
		perror("fsync result");
		return 1;
	}

	munlock(&buffers, sizeof(buffers));
	close(result_fd);
	close(device_fd);
	return panic_rc == 0 && kasan_rc == 0 ? 0 : 1;
}
