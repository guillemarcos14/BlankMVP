package com.blanknfc.app.data

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class PurchaseUiState(
    val products: List<ProductDetails> = emptyList(),
    val purchasedProductIds: Set<String> = emptySet(),
    val isLoading: Boolean = false,
    val isPurchasing: Boolean = false,
    val message: String? = null
) {
    val hasPremiumAccess: Boolean
        get() = purchasedProductIds.isNotEmpty()
}

class PlayPurchaseStore(
    context: Context,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) : PurchasesUpdatedListener {
    private val appContext = context.applicationContext
    private val _state = MutableStateFlow(PurchaseUiState())
    val state: StateFlow<PurchaseUiState> = _state.asStateFlow()

    private val billingClient = BillingClient.newBuilder(appContext)
        .setListener(this)
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder()
                .enableOneTimeProducts()
                .build()
        )
        .build()

    fun start() {
        if (billingClient.isReady) {
            loadProducts()
            refreshPurchases()
            return
        }
        _state.value = _state.value.copy(isLoading = true)
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    loadProducts()
                    refreshPurchases()
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        message = "Subscriptions are not available yet."
                    )
                }
            }

            override fun onBillingServiceDisconnected() = Unit
        })
    }

    fun loadProducts() {
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                productIds.map { id ->
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(id)
                        .setProductType(BillingClient.ProductType.SUBS)
                        .build()
                }
            )
            .build()
        billingClient.queryProductDetailsAsync(params) { result, products ->
            _state.value = _state.value.copy(
                products = if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    products.productDetailsList.sortedBy { productIds.indexOf(it.productId) }
                } else {
                    emptyList()
                },
                isLoading = false,
                message = if (result.responseCode == BillingClient.BillingResponseCode.OK && products.productDetailsList.isNotEmpty()) {
                    null
                } else {
                    "Subscriptions are not available yet."
                }
            )
        }
    }

    fun purchase(activity: Activity, productId: String) {
        val product = _state.value.products.firstOrNull { it.productId == productId }
        val offerToken = product?.subscriptionOfferDetails?.firstOrNull()?.offerToken
        if (product == null || offerToken == null) {
            _state.value = _state.value.copy(message = "This subscription is not available yet.")
            return
        }
        val productParams = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(product)
            .setOfferToken(offerToken)
            .build()
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productParams))
            .build()
        _state.value = _state.value.copy(isPurchasing = true, message = null)
        billingClient.launchBillingFlow(activity, params)
    }

    fun restorePurchases() {
        refreshPurchases("Purchase restored.")
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            handlePurchases(purchases)
        } else {
            _state.value = _state.value.copy(
                isPurchasing = false,
                message = if (result.responseCode == BillingClient.BillingResponseCode.USER_CANCELED) {
                    "Purchase cancelled."
                } else {
                    "Purchase could not be completed."
                }
            )
        }
    }

    fun priceText(productId: String, fallback: String): String {
        val product = _state.value.products.firstOrNull { it.productId == productId }
        val phase = product?.subscriptionOfferDetails
            ?.firstOrNull()
            ?.pricingPhases
            ?.pricingPhaseList
            ?.lastOrNull()
        return phase?.formattedPrice ?: fallback
    }

    private fun refreshPurchases(successMessage: String? = null) {
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()
        billingClient.queryPurchasesAsync(params) { result, purchases ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                handlePurchases(purchases, successMessage)
            } else {
                _state.value = _state.value.copy(isLoading = false, isPurchasing = false)
            }
        }
    }

    private fun handlePurchases(purchases: List<Purchase>, successMessage: String? = null) {
        val activeIds = purchases
            .filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }
            .flatMap { purchase ->
                if (!purchase.isAcknowledged) {
                    acknowledge(purchase)
                }
                purchase.products
            }
            .filter { it in productIds }
            .toSet()
        _state.value = _state.value.copy(
            purchasedProductIds = activeIds,
            isLoading = false,
            isPurchasing = false,
            message = successMessage
        )
    }

    private fun acknowledge(purchase: Purchase) {
        scope.launch {
            val params = AcknowledgePurchaseParams.newBuilder()
                .setPurchaseToken(purchase.purchaseToken)
                .build()
            billingClient.acknowledgePurchase(params) {}
        }
    }

    companion object {
        const val monthlyProductId = "blanked_monthly_299"
        const val annualProductId = "blanked_annual_19"
        val productIds = listOf(monthlyProductId, annualProductId)
    }
}
