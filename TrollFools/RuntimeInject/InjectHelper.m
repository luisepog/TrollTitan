#import "InjectHelper.h"
#import "rop_inject.h"
#import "libproc.h"
#import <mach/mach.h>
#import <mach/task_info.h>
#import <mach/mach_host.h>
#import <mach/processor_set.h>

static task_t GetTaskByPid(pid_t pid)
{
    host_t host = mach_host_self();
    processor_set_name_t psDefault = MACH_PORT_NULL;
    kern_return_t kr = processor_set_default(host, &psDefault);
    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(psDefault)) {
        return MACH_PORT_NULL;
    }

    processor_set_t psDefaultControl = MACH_PORT_NULL;
    kr = host_processor_set_priv(host, psDefault, &psDefaultControl);
    if (kr != KERN_SUCCESS || !MACH_PORT_VALID(psDefaultControl)) {
        mach_port_deallocate(mach_task_self(), psDefault);
        return MACH_PORT_NULL;
    }

    task_array_t tasks = NULL;
    mach_msg_type_number_t numTasks = 0;
    kr = processor_set_tasks(psDefaultControl, &tasks, &numTasks);
    if (kr != KERN_SUCCESS || !tasks || numTasks == 0) {
        mach_port_deallocate(mach_task_self(), psDefault);
        mach_port_deallocate(mach_task_self(), psDefaultControl);
        return MACH_PORT_NULL;
    }

    task_t resultTask = MACH_PORT_NULL;
    for (mach_msg_type_number_t i = 0; i < numTasks; i++) {
        pid_t taskPid = 0;
        kr = pid_for_task(tasks[i], &taskPid);
        if (kr != KERN_SUCCESS) continue;
        if (taskPid == pid) {
            resultTask = tasks[i];
            break;
        }
    }

    vm_deallocate(mach_task_self(), (vm_address_t)tasks, numTasks * sizeof(task_t));
    mach_port_deallocate(mach_task_self(), psDefault);
    mach_port_deallocate(mach_task_self(), psDefaultControl);

    return resultTask;
}

static BOOL injectDylibIntoProcessNamed(NSString *processNameSubstring, NSString *dylibPath)
{
    if (processNameSubstring.length == 0 || dylibPath.length == 0) return NO;

    const char *targetName = [processNameSubstring UTF8String];
    const char *dylibFSPath = [dylibPath fileSystemRepresentation];

    int count = proc_listallpids(NULL, 0);
    if (count <= 0) return NO;

    pid_t *pids = malloc((size_t)count * sizeof(pid_t));
    if (!pids) return NO;

    int actualCount = proc_listallpids(pids, (int)((size_t)count * sizeof(pid_t)));
    if (actualCount <= 0) {
        free(pids);
        return NO;
    }

    BOOL success = NO;
    for (int i = 0; i < actualCount; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;

        char name[1000];
        memset(name, 0, sizeof(name));
        if (proc_name(pid, name, sizeof(name)) <= 0) continue;
        if (strstr(name, targetName) == NULL) continue;

        task_t task = MACH_PORT_NULL;
        kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
        if (kr != KERN_SUCCESS || !MACH_PORT_VALID(task)) {
            task = GetTaskByPid(pid);
        }

        if (!MACH_PORT_VALID(task)) continue;

        task_dyld_info_data_t dyldInfo;
        mach_msg_type_number_t infoCount = TASK_DYLD_INFO_COUNT;
        kr = task_info(task, TASK_DYLD_INFO, (task_info_t)&dyldInfo, &infoCount);
        if (kr != KERN_SUCCESS) {
            mach_port_deallocate(mach_task_self(), task);
            continue;
        }

        injectDylibViaRop(task, pid, dylibFSPath, dyldInfo.all_image_info_addr);
        mach_port_deallocate(mach_task_self(), task);
        success = YES;
        break;
    }

    free(pids);
    return success;
}

BOOL TrollTitanInjectDylibIntoProcess(NSString *processNameSubstring, NSString *dylibPath)
{
    return injectDylibIntoProcessNamed(processNameSubstring, dylibPath);
}
