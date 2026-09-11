#include <linux/module.h>
#include <linux/proc_fs.h>
#include <linux/kernel.h>
#include <linux/miscdevice.h>
#include <linux/vmalloc.h>
#include <linux/mm.h>
#include <linux/highmem.h>
#include <linux/slab.h>

#define CMD_ALLOC               0x1010
#define CMD_FREE                0x1111
#define CMD_OOB_WRITE           0x1212
#define CMD_DWP                 0x1313

#define HELPER_LOG              0x2222
#define HELPER_AAR              0x2323
#define HELPER_AAW              0x2424  


#define NUM_OBJS              0x100

struct vuln_obj* objs[NUM_OBJS];
unsigned long oob_window_start = 0;

struct vuln_obj{
    void* pointer;
    char data[];
};

struct vuln_req {
    unsigned long idx;
    unsigned long alloc_len;
    void __user *user_buf;
    size_t user_buf_len;
    unsigned long address;
    unsigned long value; 
    char is_oob_write;
    char is_logged;

};

static long vuln_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
    struct vuln_req req;
    unsigned long idx;

    int ret = 0;
    ret = copy_from_user(&req, (struct vuln_req __user *)arg, sizeof(req));
        if (ret != 0) {
        pr_err("vuln: copy_from_user failed\n");
        return -EFAULT;
    }
    idx = req.idx;
        

    switch (cmd) {
    case CMD_ALLOC:
        if (idx > NUM_OBJS) {
            ret = -EINVAL;
            break;
        }
        objs[idx] = (struct vuln_obj*) kmalloc(req.alloc_len, GFP_KERNEL);
        if (!objs[idx]) {
            pr_err("vuln: kmalloc failed\n");
            return -ENOMEM;
        }
        if(req.user_buf && req.user_buf_len <= req.alloc_len) {
            ret = copy_from_user(objs[idx], req.user_buf, req.user_buf_len);
            if (ret != 0) {
                pr_err("vuln: copy_from_user failed\n");
            }
        }
        if (req.is_logged)
            pr_info("vuln: Allocated object %lu of size %lu at %lx\n", idx, req.alloc_len,(unsigned long)objs[idx]);
        break;

    case CMD_FREE:
        if (idx > NUM_OBJS || !objs[idx]) {
            ret = -EINVAL;
            break;
        }
        if (req.is_logged)
            pr_info("vuln: Freeing object %lu at %lx\n", idx, (unsigned long)objs[idx]);
        kfree(objs[idx]);
        break;


    case CMD_OOB_WRITE:
        if (req.is_oob_write && req.user_buf_len > req.alloc_len){
            pr_info("vuln: OOB write\n");
            pr_info("OOB object address: %lx\n", (unsigned long)objs[idx]);
        }
        else
            pr_info("vuln: normal write (cache training)\n");
        
        if (idx >= NUM_OBJS || !objs[idx]) {
            ret = -EINVAL;
            break;
        }
        // Copy user buffer to kernel buffer in advance (CONFIG_HARDENED_USERCOPY)
        char* buf = kmalloc(req.user_buf_len, GFP_KERNEL);
        if (!buf) {
            pr_err("vuln: kmalloc failed\n");
            return -ENOMEM;
        }
        ret = copy_from_user(buf, req.user_buf, req.user_buf_len);
        if (ret != 0) {
            pr_err("vuln: copy_from_user failed\n");
            kfree(buf);
            return -EFAULT;
        }

        // OOB Write
        oob_window_start = __arch_counter_get_cntvct();
        memcpy(objs[idx], buf, req.user_buf_len);
        kfree(buf);
        break;
    
    case CMD_DWP:
        pr_info("vuln: Dereference Write Primitive\n");
        pr_info("vuln: DWP object address: %lx\n", (unsigned long)objs[idx]);
        if (idx >= NUM_OBJS || !objs[idx]) {
            ret = -EINVAL;
            break;
        }
        // Dereference Write Primitive
        unsigned long* target_addr = (unsigned long*)objs[idx]->pointer;
        *target_addr = req.value;
        break;

    case HELPER_LOG:
        pr_info("vuln: Log Command\n");
        pr_info("vuln: oob_window_start: %lx\n", oob_window_start);
        break;

    case HELPER_AAR:
        pr_info("vuln: Arbitrary Address Read\n");
        ret = copy_to_user(req.user_buf, (unsigned long*)req.address, sizeof(unsigned long));
        if (ret != 0)
            ret = -EFAULT;
        break;

    case HELPER_AAW:
        pr_info("vuln: Arbitrary Address Write\n");
        *((unsigned long*)req.address) = req.value;
        break;
    
    default:
        pr_info("vuln: Invalid `cmd` %u\n", cmd);
        ret = -EINVAL;
        break;
    }

    return ret;
}

static const struct file_operations vuln_fops = {
    .owner          = THIS_MODULE,
    .unlocked_ioctl = vuln_ioctl,
};

static struct miscdevice vuln_miscdev = {
    .minor = MISC_DYNAMIC_MINOR,
    .name = "vuln",
    .fops = &vuln_fops,
    .mode = 0666,
};

static int __init vuln_init(void)
{
    pr_info("vuln: module loaded\n");
    return misc_register(&vuln_miscdev);
}

static void __exit vuln_exit(void)
{
    pr_info("vuln: module unloaded\n");
    misc_deregister(&vuln_miscdev);
}

module_init(vuln_init);
module_exit(vuln_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Vulnerable kernel module for MTEscape evaluation");
MODULE_AUTHOR("Anonymous Submission");