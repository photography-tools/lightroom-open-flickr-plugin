local LrDialogs = import "LrDialogs"

require "FlickrAPI"
local logger = import 'LrLogger'( 'FlickrAPI' )
logger:enable('logfile')


return {
    URLHandler = function ( url )
        logger:info("URLCallback", url)
        if FlickrAPI.URLCallback then
            FlickrAPI.URLCallback( url:match( "code=([^&]+)" ) )
        end
    end
}
