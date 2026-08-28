#include "CAuthorizationPlugin.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

extern int32_t BCUAuthorizationPluginConsumeLease(void);

typedef struct {
    const AuthorizationCallbacks *callbacks;
} BCUPlugin;

typedef struct {
    BCUPlugin *plugin;
    AuthorizationEngineRef engine;
    pthread_mutex_t lock;
    pthread_cond_t idle;
    Boolean resolved;
    Boolean invoking;
    Boolean committing;
    Boolean deactivated;
} BCUMechanism;

static OSStatus BCUPluginDestroy(AuthorizationPluginRef pluginRef) {
    free(pluginRef);
    return errAuthorizationSuccess;
}

static OSStatus BCUMechanismCreate(
    AuthorizationPluginRef pluginRef,
    AuthorizationEngineRef engine,
    AuthorizationMechanismId mechanismId,
    AuthorizationMechanismRef *outMechanism
) {
    if (pluginRef == NULL || engine == NULL || mechanismId == NULL || outMechanism == NULL) {
        return errAuthorizationInternal;
    }
    if (strcmp(mechanismId, "remote") != 0) {
        return errAuthorizationDenied;
    }
    BCUMechanism *mechanism = calloc(1, sizeof(BCUMechanism));
    if (mechanism == NULL) {
        return errAuthorizationInternal;
    }
    mechanism->plugin = (BCUPlugin *)pluginRef;
    mechanism->engine = engine;
    if (pthread_mutex_init(&mechanism->lock, NULL) != 0) {
        free(mechanism);
        return errAuthorizationInternal;
    }
    if (pthread_cond_init(&mechanism->idle, NULL) != 0) {
        pthread_mutex_destroy(&mechanism->lock);
        free(mechanism);
        return errAuthorizationInternal;
    }
    mechanism->resolved = false;
    mechanism->invoking = false;
    mechanism->committing = false;
    mechanism->deactivated = false;
    *outMechanism = mechanism;
    return errAuthorizationSuccess;
}

static OSStatus BCUMechanismInvoke(AuthorizationMechanismRef mechanismRef) {
    BCUMechanism *mechanism = (BCUMechanism *)mechanismRef;
    if (mechanism == NULL || mechanism->plugin == NULL || mechanism->plugin->callbacks == NULL) {
        return errAuthorizationInternal;
    }
    pthread_mutex_lock(&mechanism->lock);
    if (mechanism->resolved) {
        pthread_mutex_unlock(&mechanism->lock);
        return errAuthorizationSuccess;
    }
    mechanism->resolved = true;
    mechanism->invoking = true;
    Boolean deactivatedBeforeConsume = mechanism->deactivated;
    pthread_mutex_unlock(&mechanism->lock);

    Boolean leaseAllowed = !deactivatedBeforeConsume &&
        BCUAuthorizationPluginConsumeLease() == 1;

    pthread_mutex_lock(&mechanism->lock);
    AuthorizationResult result = leaseAllowed && !mechanism->deactivated
        ? kAuthorizationResultAllow
        : kAuthorizationResultDeny;
    mechanism->committing = true;
    pthread_mutex_unlock(&mechanism->lock);

    OSStatus status = mechanism->plugin->callbacks->SetResult(mechanism->engine, result);

    pthread_mutex_lock(&mechanism->lock);
    mechanism->committing = false;
    mechanism->invoking = false;
    pthread_cond_broadcast(&mechanism->idle);
    pthread_mutex_unlock(&mechanism->lock);
    return status;
}

static OSStatus BCUMechanismDeactivate(AuthorizationMechanismRef mechanismRef) {
    BCUMechanism *mechanism = (BCUMechanism *)mechanismRef;
    if (mechanism == NULL || mechanism->plugin == NULL || mechanism->plugin->callbacks == NULL) {
        return errAuthorizationInternal;
    }
    pthread_mutex_lock(&mechanism->lock);
    mechanism->deactivated = true;
    while (mechanism->committing) {
        pthread_cond_wait(&mechanism->idle, &mechanism->lock);
    }
    pthread_mutex_unlock(&mechanism->lock);
    return mechanism->plugin->callbacks->DidDeactivate(mechanism->engine);
}

static OSStatus BCUMechanismDestroy(AuthorizationMechanismRef mechanismRef) {
    BCUMechanism *mechanism = (BCUMechanism *)mechanismRef;
    if (mechanism == NULL) {
        return errAuthorizationSuccess;
    }
    pthread_mutex_lock(&mechanism->lock);
    mechanism->deactivated = true;
    while (mechanism->invoking) {
        pthread_cond_wait(&mechanism->idle, &mechanism->lock);
    }
    pthread_mutex_unlock(&mechanism->lock);
    pthread_cond_destroy(&mechanism->idle);
    pthread_mutex_destroy(&mechanism->lock);
    free(mechanism);
    return errAuthorizationSuccess;
}

static const AuthorizationPluginInterface BCUPluginInterface = {
    .version = kAuthorizationPluginInterfaceVersion,
    .PluginDestroy = BCUPluginDestroy,
    .MechanismCreate = BCUMechanismCreate,
    .MechanismInvoke = BCUMechanismInvoke,
    .MechanismDeactivate = BCUMechanismDeactivate,
    .MechanismDestroy = BCUMechanismDestroy,
};

OSStatus AuthorizationPluginCreate(
    const AuthorizationCallbacks *callbacks,
    AuthorizationPluginRef *outPlugin,
    const AuthorizationPluginInterface **outPluginInterface
) {
    if (callbacks == NULL || outPlugin == NULL || outPluginInterface == NULL ||
        callbacks->version < kAuthorizationCallbacksVersion) {
        return errAuthorizationInternal;
    }
    BCUPlugin *plugin = calloc(1, sizeof(BCUPlugin));
    if (plugin == NULL) {
        return errAuthorizationInternal;
    }
    plugin->callbacks = callbacks;
    *outPlugin = plugin;
    *outPluginInterface = &BCUPluginInterface;
    return errAuthorizationSuccess;
}

UInt32 BCUAuthorizationPluginInterfaceVersion(void) {
    return kAuthorizationPluginInterfaceVersion;
}
