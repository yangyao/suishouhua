package com.suishouhua.tv.net

import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Enumeration

/** 取电视局域网 IPv4 地址（用于二维码 payload）。 */
object IpUtil {

    fun lanIpv4(): String? {
        val candidates = mutableListOf<Pair<Int, String>>() // priority to ip
        val nis: Enumeration<NetworkInterface> = NetworkInterface.getNetworkInterfaces() ?: return null
        while (nis.hasMoreElements()) {
            val ni = nis.nextElement()
            if (!ni.isUp || ni.isLoopback) continue
            val addrs = ni.inetAddresses ?: continue
            while (addrs.hasMoreElements()) {
                val addr = addrs.nextElement() as? Inet4Address ?: continue
                if (addr.isLoopbackAddress) continue
                val ip = addr.hostAddress ?: continue
                if (!addr.isSiteLocalAddress) continue
                // 优先 wlan（电视 Wi-Fi 连接），其次 eth
                val priority = when {
                    ni.name.startsWith("wlan") -> 0
                    ni.name.startsWith("eth") -> 1
                    else -> 2
                }
                candidates.add(priority to ip)
            }
        }
        return candidates.minByOrNull { it.first }?.second
    }
}
