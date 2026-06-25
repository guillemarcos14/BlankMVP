package com.blanknfc.app.util

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Bundle

object NfcHelper {

    fun extractUid(tag: Tag): String {
        return tag.id.joinToString("") { "%02X".format(it) }
    }

    fun extractUidFromIntent(intent: Intent): String? {
        val tag = intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)
        return tag?.let { extractUid(it) }
    }

    fun enableForegroundDispatch(activity: Activity) {
        val adapter = NfcAdapter.getDefaultAdapter(activity) ?: return
        val intent = Intent(activity, activity.javaClass).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            activity, 0, intent,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val filters = arrayOf(
            IntentFilter(NfcAdapter.ACTION_TAG_DISCOVERED)
        )
        adapter.enableForegroundDispatch(activity, pendingIntent, filters, null)
    }

    fun enableReaderMode(activity: Activity, onTagDiscovered: (String) -> Unit) {
        val adapter = NfcAdapter.getDefaultAdapter(activity) ?: return
        val flags = NfcAdapter.FLAG_READER_NFC_A or
            NfcAdapter.FLAG_READER_NFC_B or
            NfcAdapter.FLAG_READER_NFC_F or
            NfcAdapter.FLAG_READER_NFC_V or
            NfcAdapter.FLAG_READER_NFC_BARCODE or
            NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK
        adapter.enableReaderMode(
            activity,
            { tag -> onTagDiscovered(extractUid(tag)) },
            flags,
            Bundle()
        )
    }

    fun disableReaderMode(activity: Activity) {
        val adapter = NfcAdapter.getDefaultAdapter(activity) ?: return
        adapter.disableReaderMode(activity)
    }

    fun disableForegroundDispatch(activity: Activity) {
        val adapter = NfcAdapter.getDefaultAdapter(activity) ?: return
        adapter.disableForegroundDispatch(activity)
    }

    fun isNfcEnabled(activity: Activity): Boolean {
        return isNfcEnabled(activity as Context)
    }

    fun isNfcEnabled(context: Context): Boolean {
        val adapter = NfcAdapter.getDefaultAdapter(context) ?: return false
        return adapter.isEnabled
    }

    fun isNfcAvailable(activity: Activity): Boolean {
        return isNfcAvailable(activity as Context)
    }

    fun isNfcAvailable(context: Context): Boolean {
        return NfcAdapter.getDefaultAdapter(context) != null
    }
}
