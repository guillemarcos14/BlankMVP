package com.brickmvp.app.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.brickmvp.app.data.SessionManager
import com.brickmvp.app.ui.screens.AppSelectorScreen
import com.brickmvp.app.ui.screens.HomeScreen
import com.brickmvp.app.ui.screens.SetupScreen

object Routes {
    const val SETUP = "setup"
    const val HOME = "home"
    const val APP_SELECTOR = "app_selector"
}

@Composable
fun NavGraph(
    navController: NavHostController,
    sessionManager: SessionManager,
    startDestination: String
) {
    NavHost(navController = navController, startDestination = startDestination) {
        composable(Routes.SETUP) {
            SetupScreen(
                sessionManager = sessionManager,
                onSetupComplete = {
                    sessionManager.setSetupComplete()
                    navController.navigate(Routes.HOME) {
                        popUpTo(Routes.SETUP) { inclusive = true }
                    }
                },
                onNavigateToAppSelector = {
                    navController.navigate(Routes.APP_SELECTOR)
                }
            )
        }
        composable(Routes.HOME) {
            HomeScreen(
                sessionManager = sessionManager,
                onEditApps = {
                    navController.navigate(Routes.APP_SELECTOR)
                },
                onForgetTag = {
                    sessionManager.forgetNfcTag()
                    navController.navigate(Routes.SETUP) {
                        popUpTo(Routes.HOME) { inclusive = true }
                    }
                }
            )
        }
        composable(Routes.APP_SELECTOR) {
            AppSelectorScreen(
                sessionManager = sessionManager,
                onBack = { navController.popBackStack() }
            )
        }
    }
}
