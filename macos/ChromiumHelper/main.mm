#include "include/cef_api_hash.h"
#include "include/capi/cef_app_capi.h"

int main(int argc, char *argv[]) {
    (void)cef_api_hash(CEF_API_VERSION, 0);

    cef_main_args_t mainArgs = {};
    mainArgs.argc = argc;
    mainArgs.argv = argv;
    return cef_execute_process(&mainArgs, nullptr, nullptr);
}
