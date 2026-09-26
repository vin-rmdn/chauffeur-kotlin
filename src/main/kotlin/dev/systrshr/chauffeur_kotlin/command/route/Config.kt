package dev.systrshr.chauffeur_kotlin.command.route

data class GoogleCloud(val mapsApiKey: String)
data class Config(val googleCloud: GoogleCloud)
