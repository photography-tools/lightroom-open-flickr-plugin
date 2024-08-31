-- Lightroom SDK
local LrBinding = import 'LrBinding'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrErrors = import 'LrErrors'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrHttp = import 'LrHttp'
local LrMD5 = import 'LrMD5'
local LrPathUtils = import 'LrPathUtils'
local LrStringUtils = import "LrStringUtils"
local LrView = import 'LrView'
local LrXml = import 'LrXml'

local prefs = import 'LrPrefs'.prefsForPlugin()

local bind = LrView.bind
local share = LrView.share

local logger = import 'LrLogger'( 'FlickrAPI' )
logger:enable('logfile')

--============================================================================--

local API_KEY = "" -- Your Flickr API key
local API_SECRET = "" -- Your Flickr API secret
local API_ENDPOINT = "https://api.flickr.com/services/rest/"
local AUTH_ENDPOINT = "https://www.flickr.com/services/oauth/request_token"
local ACCESS_TOKEN_ENDPOINT = "https://www.flickr.com/services/oauth/access_token"
local AUTHORIZE_URL = "https://www.flickr.com/services/oauth/authorize"
local USER_AGENT = "Lightroom Flickr Plugin 0.1.0"

require "sha1"

FlickrAPI = {}

--------------------------------------------------------------------------------

local function formatError( nativeErrorCode )
    return LOC "$$$/GPhoto/Error/NetworkFailure=Could not connect to Flickr. Please check your Internet connection."
end

--------------------------------------------------------------------------------

local function trim( s )
    return string.gsub( s, "^%s*(.-)%s*$", "%1" )
end

--------------------------------------------------------------------------------

local function url_encode(str)
    if (str) then
        str = string.gsub (str, "\n", "\r\n")
        str = string.gsub (str, "([^%w %-%_%.%~])",
            function (c) return string.format ("%%%02X", string.byte(c)) end)
        str = string.gsub (str, " ", "+")
    end
    return str
end

local function oauth_encode( value )
    return url_encode(tostring(value))
end

local function generate_nonce()
    return LrMD5.digest( tostring(math.random()) .. tostring(LrDate.currentTime()) )
end

local function oauth_sign( method, url, params )
    local keys = {}
    for key in pairs(params) do
        table.insert(keys, key)
    end
    table.sort(keys)

    local base_string = method .. "&" .. oauth_encode(url) .. "&"
    local params_string = ""
    for i, key in ipairs(keys) do
        params_string = params_string .. key .. "=" .. oauth_encode(params[key])
        if i < #keys then
            params_string = params_string .. "&"
        end
    end
    base_string = base_string .. oauth_encode(params_string)

    local signing_key = API_SECRET .. "&" .. (params.oauth_token_secret or "")
    return hmac_sha1_binary(signing_key, base_string)
end

--------------------------------------------------------------------------------

function FlickrAPI.convertIds( photoId )
    return { photoId }
end

function FlickrAPI.uploadPhoto( propertyTable, params )
    assert( type( params ) == 'table', 'FlickrAPI.uploadPhoto: params must be a table' )
    logger:info( 'uploadPhoto: ', params.filePath )

    local filePath = assert( params.filePath )
    local fileName = LrPathUtils.leafName( filePath )

    local uploadParams = {
        oauth_consumer_key = API_KEY,
        oauth_nonce = generate_nonce(),
        oauth_signature_method = "HMAC-SHA1",
        oauth_timestamp = tostring(os.time()),
        oauth_token = propertyTable.access_token,
        oauth_version = "1.0",
        title = fileName,
    }

    if params.albumId then
        uploadParams.album_id = params.albumId
    end

    uploadParams.oauth_signature = oauth_sign("POST", "https://up.flickr.com/services/upload/", uploadParams)

    local postBody = {}
    for k, v in pairs(uploadParams) do
        table.insert(postBody, { name = k, value = v })
    end
    table.insert(postBody, { name = "photo", filePath = filePath })

    local resultRaw, hdrs = LrHttp.postMultipart("https://up.flickr.com/services/upload/", postBody)

    if not resultRaw then
        if hdrs and hdrs.error then
            LrErrors.throwUserError( formatError( hdrs.error.nativeCode ) )
        end
    end

    local xml = LrXml.parseXml(resultRaw)
    local photoId = xml:childAtPath("photoid"):text()

    if photoId then
        logger:info(string.format("upload successful: Photo ID: %s, Album ID: %s", photoId, params.albumId))
        return photoId
    else
        logger:info("upload end: exception")
        LrErrors.throwUserError( LOC( "$$$/GPhoto/Error/API/Upload=Flickr API returned an error message (function upload, message ^1)",
            'error message' ) )
    end
end

--------------------------------------------------------------------------------
function FlickrAPI.refreshToken(propertyTable)
    logger:trace('refreshToken invoked')
    -- Flickr doesn't have refresh tokens, so we'll just return the existing access token
    return propertyTable.access_token
end

--------------------------------------------------------------------------------
function FlickrAPI.login(context, consumer_key, consumer_secret)
    local properties = LrBinding.makePropertyTable( context )
    local f = LrView.osFactory()

    -- Step 1: Get request token
    local requestTokenParams = {
        oauth_consumer_key = API_KEY,
        oauth_nonce = generate_nonce(),
        oauth_signature_method = "HMAC-SHA1",
        oauth_timestamp = tostring(os.time()),
        oauth_callback = "oob",
        oauth_version = "1.0",
    }
    requestTokenParams.oauth_signature = oauth_sign("GET", AUTH_ENDPOINT, requestTokenParams)

    local requestTokenUrl = AUTH_ENDPOINT .. "?" .. url_encode(requestTokenParams)
    local response = LrHttp.get(requestTokenUrl)

    local requestToken, requestTokenSecret
    for key, value in string.gmatch(response, "([^&=]+)=([^&=]+)") do
        if key == "oauth_token" then requestToken = value
        elseif key == "oauth_token_secret" then requestTokenSecret = value end
    end

    -- Step 2: Authorize
    local authorizeUrl = AUTHORIZE_URL .. "?oauth_token=" .. requestToken .. "&perms=write"
    LrHttp.openUrlInBrowser(authorizeUrl)

    local contents = f:column {
        bind_to_object = properties,
        spacing = f:control_spacing(),
        f:static_text {
            title = "Enter the verification code provided by Flickr",
            place_horizontal = 0.5,
        },
        f:edit_field {
            width = 300,
            value = bind "verifier",
            place_horizontal = 0.5,
        },
    }

    local action = LrDialogs.presentModalDialog({
        title = "Enter verification code",
        contents = contents,
        actionVerb = "Authorize"
    })

    if action == "cancel" or not properties.verifier then return nil end

    -- Step 3: Get access token
    local accessTokenParams = {
        oauth_consumer_key = API_KEY,
        oauth_nonce = generate_nonce(),
        oauth_signature_method = "HMAC-SHA1",
        oauth_timestamp = tostring(os.time()),
        oauth_token = requestToken,
        oauth_verifier = properties.verifier,
        oauth_version = "1.0",
    }
    accessTokenParams.oauth_signature = oauth_sign("GET", ACCESS_TOKEN_ENDPOINT, accessTokenParams)

    local accessTokenUrl = ACCESS_TOKEN_ENDPOINT .. "?" .. url_encode(accessTokenParams)
    response = LrHttp.get(accessTokenUrl)

    local accessToken, accessTokenSecret, userId, username
    for key, value in string.gmatch(response, "([^&=]+)=([^&=]+)") do
        if key == "oauth_token" then accessToken = value
        elseif key == "oauth_token_secret" then accessTokenSecret = value
        elseif key == "user_nsid" then userId = value
        elseif key == "username" then username = value end
    end

    if not accessToken or not accessTokenSecret then
        LrErrors.throwUserError( "Login failed." )
    end
    logger:info("Login succeeded")
    return {
        access_token = accessToken,
        access_token_secret = accessTokenSecret,
        user_id = userId,
        username = username,
    }
end

function FlickrAPI.listAlbums(propertyTable)
    logger:trace("listAlbums")

    local params = {
        method = "flickr.photosets.getList",
        oauth_consumer_key = API_KEY,
        oauth_nonce = generate_nonce(),
        oauth_signature_method = "HMAC-SHA1",
        oauth_timestamp = tostring(os.time()),
        oauth_token = propertyTable.access_token,
        oauth_version = "1.0",
        format = "json",
        nojsoncallback = 1,
    }
    params.oauth_signature = oauth_sign("GET", API_ENDPOINT, params)

    local url = API_ENDPOINT .. "?" .. url_encode(params)
    local result, hdrs = LrHttp.get(url)

    local json = require 'json'
    local response = json.decode(result)

    if response and response.photosets and response.photosets.photoset then
        return response.photosets.photoset
    else
        return {}
    end
end

function FlickrAPI.findOrCreateAlbum(propertyTable, albumName)
    logger:trace("findOrCreateAlbum")
    local albums = FlickrAPI.listAlbums(propertyTable)

    for _, album in ipairs(albums) do
        if album.title._content == albumName then
            logger:info("Album found:", album.id)
            return album.id
        end
    end

    -- Create new album
    local params = {
        method = "flickr.photosets.create",
        oauth_consumer_key = API_KEY,
        oauth_nonce = generate_nonce(),
        oauth_signature_method = "HMAC-SHA1",
        oauth_timestamp = tostring(os.time()),
        oauth_token = propertyTable.access_token,
        oauth_version = "1.0",
        title = albumName,
        format = "json",
        nojsoncallback = 1,
    }
    params.oauth_signature = oauth_sign("POST", API_ENDPOINT, params)

    local postBody = ""
    for k, v in pairs(params) do
        postBody = postBody .. k .. "=" .. url_encode(v) .. "&"
    end
    postBody = postBody:sub(1, -2)  -- Remove trailing &

    local result, hdrs = LrHttp.post(API_ENDPOINT, postBody, {
        { field = "Content-Type", value = "application/x-www-form-urlencoded" },
    })

    local json = require 'json'
    local response = json.decode(result)

    if response and response.photoset and response.photoset.id then
        logger:info("Album created:", response.photoset.id)
        return response.photoset.id
    else
        LrErrors.throwUserError("Failed to create album")
    end
end