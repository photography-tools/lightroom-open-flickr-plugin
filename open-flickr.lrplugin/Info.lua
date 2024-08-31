return {
	LrSdkVersion = 3.0,
	LrSdkMinimumVersion = 3.0, -- minimum SDK version required by this plug-in

	LrToolkitIdentifier = 'org.photography-tools.lightroom-google-photo-plugin',
	LrPluginName = LOC "$$$/GPhoto/PluginName=OpenFlickr",

	LrExportServiceProvider = {
		title = LOC "$$$/GPhoto/GPhoto-title=Open Flickr",
		file = 'GPhotoExportServiceProvider.lua',
	},
	LrMetadataProvider = 'GPhotoMetadataDefinition.lua',
	URLHandler = "GPhotoURLHandler.lua",
	VERSION = { major=0, minor=1, revision=0 },
}
