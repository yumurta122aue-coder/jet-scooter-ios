/*
 * unpin_flutter.js — Frida unpinning for a Flutter client
 *
 * Contingency only. The static analysis says the JET client does not pin, so run
 * the proxy capture first and only reach for this if the handshake fails.
 *
 * Flutter does its networking in Dart, over BoringSSL compiled into
 * libflutter.so. Java-level unpinning scripts do nothing for it, which is why
 * most "universal SSL bypass" scripts fail on Flutter apps. The two hooks that
 * matter are below.
 *
 * Usage:
 *   frida -U -f <package> -l unpin_flutter.js --no-pause
 *
 * Requires a rooted device or an emulator, and frida-server running as root.
 */

'use strict';

function log(msg) {
    console.log('[unpin] ' + msg);
}

/* ------------------------------------------------------------------ *
 * 1. Flutter / Dart — BoringSSL inside libflutter.so
 * ------------------------------------------------------------------ */

function hookFlutter() {
    var mod = Process.findModuleByName('libflutter.so');
    if (!mod) {
        log('libflutter.so not loaded yet — will retry');
        return false;
    }
    log('libflutter.so at ' + mod.base);

    // ssl_verify_cert_chain is the single choke point where the chain verdict
    // is produced. Forcing it to 1 accepts whatever the proxy presents.
    var verify = Module.findExportByName('libflutter.so', 'ssl_verify_cert_chain');
    if (verify) {
        Interceptor.replace(verify, new NativeCallback(function (ssl, chain) {
            log('ssl_verify_cert_chain -> accept');
            return 1;
        }, 'int', ['pointer', 'pointer']));
        log('replaced ssl_verify_cert_chain');
    } else {
        log('ssl_verify_cert_chain not exported — symbols may be stripped');
    }

    // Hostname checking is separate from chain checking. Neutralising this stops
    // a "certificate is valid but the name does not match" rejection.
    var setHost = Module.findExportByName('libflutter.so', 'X509_VERIFY_PARAM_set1_host');
    if (setHost) {
        Interceptor.replace(setHost, new NativeCallback(function (param, name, len) {
            log('X509_VERIFY_PARAM_set1_host suppressed');
            return 1;
        }, 'int', ['pointer', 'pointer', 'size_t']));
        log('replaced X509_VERIFY_PARAM_set1_host');
    }

    // If the app installs a custom verify callback, this is where it lands.
    var customVerify = Module.findExportByName('libflutter.so', 'SSL_CTX_set_custom_verify');
    if (customVerify) {
        Interceptor.replace(customVerify, new NativeCallback(function (ctx, mode, cb) {
            log('SSL_CTX_set_custom_verify suppressed');
            return;
        }, 'void', ['pointer', 'int', 'pointer']));
        log('replaced SSL_CTX_set_custom_verify');
    }

    return true;
}

/* ------------------------------------------------------------------ *
 * 2. Java side — OkHttp / TrustManager, for any plugin that uses it
 * ------------------------------------------------------------------ */

function hookJava() {
    if (!Java.available) {
        log('java not available — skipping');
        return;
    }

    Java.perform(function () {
        try {
            var X509TrustManager = Java.use('javax.net.ssl.X509TrustManager');
            var SSLContext = Java.use('javax.net.ssl.SSLContext');

            var TrustManager = Java.registerClass({
                name: 'com.analysis.TrustAll',
                implements: [X509TrustManager],
                methods: {
                    checkClientTrusted: function () {},
                    checkServerTrusted: function () {},
                    getAcceptedIssuers: function () { return []; }
                }
            });

            var managers = [TrustManager.$new()];
            var ctx = SSLContext.getInstance('TLS');
            ctx.init(null, managers, null);
            SSLContext.getInstance.overload('java.lang.String').implementation = function (algo) {
                if (algo === 'TLS') {
                    log('SSLContext("TLS") -> trust-all');
                    return ctx;
                }
                return this.getInstance(algo);
            };
            log('java trust manager replaced');
        } catch (e) {
            log('java hook failed: ' + e);
        }

        // OkHttp CertificatePinner, if present.
        try {
            var Pinner = Java.use('okhttp3.CertificatePinner');
            Pinner.check.overload('java.lang.String', 'java.util.List').implementation = function () {
                log('okhttp CertificatePinner.check bypassed');
            };
            log('okhttp pinner overridden');
        } catch (e) {
            log('no okhttp CertificatePinner (fine)');
        }
    });
}

/* ------------------------------------------------------------------ */

function main() {
    if (!hookFlutter()) {
        // libflutter may load slightly after the process starts.
        var tries = 0;
        var timer = setInterval(function () {
            tries += 1;
            if (hookFlutter() || tries > 40) {
                clearInterval(timer);
                hookJava();
            }
        }, 250);
        return;
    }
    hookJava();
}

setImmediate(main);
