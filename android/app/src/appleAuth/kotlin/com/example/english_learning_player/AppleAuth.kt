package com.example.english_learning_player

import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.auth.OAuthProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

internal fun MainActivity.registerAppleAuth(engine: FlutterEngine) {
    var auth: FirebaseAuth? = null
    val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "elp/firebase_apple_auth")

    channel.setMethodCallHandler { call, result ->
        when (call.method) {
            "signIn" -> {
                val project = call.argument<String>("project")
                val apiKey = call.argument<String>("apiKey")
                val appId = call.argument<String>("appId")
                if (project.isNullOrBlank() || apiKey.isNullOrBlank() || appId.isNullOrBlank()) {
                    result.error("configuration", null, null)
                    return@setMethodCallHandler
                }

                val instance = try {
                    val options = FirebaseOptions.Builder()
                        .setProjectId(project)
                        .setApiKey(apiKey)
                        .setApplicationId(appId)
                        .build()
                    val app = FirebaseApp.getApps(applicationContext)
                        .firstOrNull { it.name == FirebaseApp.DEFAULT_APP_NAME }
                        ?: FirebaseApp.initializeApp(applicationContext, options)
                    require(app.options == options) { "Unexpected Firebase configuration" }
                    FirebaseAuth.getInstance(app)
                } catch (_: IllegalArgumentException) {
                    result.error("configuration", null, null)
                    return@setMethodCallHandler
                } catch (_: IllegalStateException) {
                    result.error("configuration", null, null)
                    return@setMethodCallHandler
                }
                auth = instance

                val pending = instance.pendingAuthResult
                val task = pending ?: run {
                    instance.signOut()
                    val provider = OAuthProvider.newBuilder("apple.com", instance).build()
                    instance.startActivityForSignInWithProvider(this, provider)
                }
                task.addOnSuccessListener { credential ->
                    val uid = credential.user?.uid
                    if (uid == null) result.error("unauthenticated", null, null)
                    else result.success(uid)
                }.addOnFailureListener { error ->
                    when ((error as? FirebaseAuthException)?.errorCode) {
                        "ERROR_WEB_CONTEXT_CANCELED" -> result.success(null)
                        "ERROR_ACCOUNT_EXISTS_WITH_DIFFERENT_CREDENTIAL",
                        "ERROR_EMAIL_ALREADY_IN_USE" -> result.error("account-link-required", null, null)
                        else -> result.error("sign-in-rejected", null, null)
                    }
                }
            }
            "getIdToken" -> {
                val instance = auth
                val user = instance?.currentUser
                if (instance == null || user == null || user.uid != call.arguments) {
                    result.error("unauthenticated", null, null)
                    return@setMethodCallHandler
                }
                user.getIdToken(false).addOnSuccessListener { token ->
                    if (token.token == null || instance.currentUser?.uid != user.uid) {
                        result.error("unauthenticated", null, null)
                    } else {
                        result.success(token.token)
                    }
                }.addOnFailureListener { error ->
                    val code = if (error is com.google.firebase.FirebaseNetworkException) {
                        "network-unavailable"
                    } else {
                        "unauthenticated"
                    }
                    result.error(code, null, null)
                }
            }
            "signOut" -> {
                auth?.signOut()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
