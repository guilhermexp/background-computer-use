#include <Security/AuthorizationPlugin.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static int result_count = 0;
static int deactivate_count = 0;
static AuthorizationResult last_result = kAuthorizationResultUndefined;

static OSStatus fake_set_result(AuthorizationEngineRef engine, AuthorizationResult result) {
    if (engine == NULL) return errAuthorizationInternal;
    result_count += 1;
    last_result = result;
    return errAuthorizationSuccess;
}

static OSStatus fake_did_deactivate(AuthorizationEngineRef engine) {
    if (engine == NULL) return errAuthorizationInternal;
    deactivate_count += 1;
    return errAuthorizationSuccess;
}

typedef OSStatus (*AuthorizationPluginCreateFunction)(
    const AuthorizationCallbacks *,
    AuthorizationPluginRef *,
    const AuthorizationPluginInterface **
);

static int run_once(const char *path) {
    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return 1;
    }
    AuthorizationPluginCreateFunction create =
        (AuthorizationPluginCreateFunction)dlsym(handle, "AuthorizationPluginCreate");
    if (create == NULL) {
        fprintf(stderr, "AuthorizationPluginCreate missing\n");
        dlclose(handle);
        return 2;
    }

    AuthorizationCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.version = kAuthorizationCallbacksVersion;
    callbacks.SetResult = fake_set_result;
    callbacks.DidDeactivate = fake_did_deactivate;

    AuthorizationPluginRef plugin = NULL;
    const AuthorizationPluginInterface *interface = NULL;
    if (create(&callbacks, &plugin, &interface) != errAuthorizationSuccess ||
        plugin == NULL || interface == NULL) {
        dlclose(handle);
        return 3;
    }

    AuthorizationMechanismRef mechanism = NULL;
    AuthorizationEngineRef engine = (AuthorizationEngineRef)(uintptr_t)1;
    if (interface->MechanismCreate(plugin, engine, "remote", &mechanism) != errAuthorizationSuccess ||
        mechanism == NULL) {
        interface->PluginDestroy(plugin);
        dlclose(handle);
        return 4;
    }

    result_count = 0;
    deactivate_count = 0;
    last_result = kAuthorizationResultUndefined;
    if (interface->MechanismInvoke(mechanism) != errAuthorizationSuccess ||
        result_count != 1 || last_result != kAuthorizationResultDeny) {
        interface->MechanismDestroy(mechanism);
        interface->PluginDestroy(plugin);
        dlclose(handle);
        return 5;
    }
    if (interface->MechanismDeactivate(mechanism) != errAuthorizationSuccess || deactivate_count != 1) {
        interface->MechanismDestroy(mechanism);
        interface->PluginDestroy(plugin);
        dlclose(handle);
        return 6;
    }
    if (interface->MechanismDestroy(mechanism) != errAuthorizationSuccess ||
        interface->PluginDestroy(plugin) != errAuthorizationSuccess) {
        dlclose(handle);
        return 7;
    }
    if (dlclose(handle) != 0) return 8;
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: plugin_host_smoke PATH\n");
        return 64;
    }
    for (int iteration = 0; iteration < 5; iteration++) {
        int status = run_once(argv[1]);
        if (status != 0) return status;
    }
    printf("plugin_host_smoke=pass iterations=5 result=deny_without_broker\n");
    return 0;
}
