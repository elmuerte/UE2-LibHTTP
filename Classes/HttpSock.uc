/*******************************************************************************
	HttpSock																	<br />
	Base of [[LibHTTP]] this implements the main network methods for connecting
	to a webserver and retreiving data from it. Binary data is not supported.	<br />
																				<br />
	Features:																	<br />
	* GET/POST support															<br />
	* Supports transparent redirecting											<br />
	* Basic Authentication support												<br />
	* Header management															<br />
	* Cookie management															<br />
	* Support for HTTP Proxy													<br />
																				<br />
	new in version 200:															<br />
	* Supports HTTP 1.1															<br />
	* Cached resolves															<br />
	* Redirection history														<br />
	* Chuncked encoding automatically decoded									<br />
	* Added connection timeout													<br />
	* More delegates															<br />
																				<br />
	new in version 300:															<br />
	* Improved easy of use:
		get(), post(), head()													<br />
	* Support for multipart/form-data											<br />
																				<br />
	Dcoumentation and Information:
		http://wiki.beyondunreal.com/wiki/LibHTTP								<br />
																				<br />
	Authors:	Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;	<br />
																				<br />
	Copyright 2003, 2004 Michiel "El Muerte" Hendriks							<br />
	Released under the Lesser Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense				<br />

	<!-- $Id: HttpSock.uc,v 1.21 2004/09/14 11:12:48 elmuerte Exp $ -->
*******************************************************************************/
/*
	TODO:
	- implement fast get (within a tick with set limits/manual transfer)
	- add HEAD support
	- add changed since
	- make cookies savable in Xs
*/
class HttpSock extends Info config;

/** LibHTTP version number */
const VERSION = 300;

/** the output buffer size */
const BUFFERSIZE = 2048;

/* HTTP request commands */
const HTTP_CONNECT	= "CONNECT";
const HTTP_DELETE	= "DELETE";
const HTTP_GET 		= "GET";
const HTTP_HEAD 	= "HEAD";
const HTTP_OPTIONS 	= "OPTIONS";
const HTTP_POST 	= "POST";
const HTTP_PUT 		= "PUT";
const HTTP_TRACE	= "TRACE";


/** constant CR LF */
var protected string CRLF;

/** The HTTP version to use. Either 1.0 or 1.1 are supported. */
var protected string HTTPVER;

////////////////////////////////////////////////////////////////////////////////
//
//   Configuration variables
//
////////////////////////////////////////////////////////////////////////////////

/** the remote host, can be passed in the url */
var(URL) config string sHostname;
/** the remote port, can be passed in the url */
var(URL) config int iPort;
/** the local port, leave zero to use a random port (adviced) */
var(URL) config int iLocalPort;
/** the username and password to use when authentication is required, can be
	passed in the url */
var(URL) config string sAuthUsername, sAuthPassword;
/** the default value for the Accept header, we only support "text / *" */
var(URL) config string DefaultAccept;

/**
	log verbosity, you probably want to leave this 0. check the [[HttpUtil]]
	class for various log levels.
*/
var(Options) config int iVerbose;
/** when set to false it won't follow redirects */
var(Options) config bool bFollowRedirect;
/** Maximum redirections to follow */
var(Options) config int iMaxRedir;
/** Send cookie data when available, defaults to true */
var(Options) config bool bSendCookies;
/** Process incoming cookies, defaults to true */
var(Options) config bool bProcCookies;
/**
	connection timeout, if the connection couldn't be established within this
	time limit it will abort the connection and call <code>OnTimeout()</code>
*/
var(Options) config float fConnectTimout;

/** Use a proxy server */
var(Proxy) globalconfig bool bUseProxy;
/** The hostname of the proxy */
var(Proxy) globalconfig string sProxyHost;
/** The proxy port */
var(Proxy) globalconfig int iProxyPort;

////////////////////////////////////////////////////////////////////////////////
//
//   runtime variables
//
////////////////////////////////////////////////////////////////////////////////

/** the requested location */
var string RequestLocation;
/** the request method */
var string RequestMethod;
/** the request headers */
var array<string> RequestHeaders;
/** the request data */
var array<string> RequestData;

/** the return headers */
var array<string> ReturnHeaders;
/** the return data */
var array<string> ReturnData;
/** The last returned HTTP status code */
var int LastStatus;

/** the cookie data instance */
var HTTPCookies Cookies;

struct RequestHistoryEntry
{
	/** method used in the request */
	var string Method;
	/** server hostname */
	var string Hostname;
	/** location, can include GET data */
	var string Location;
	/** the HTTP response code received */
	var int HTTPresponse;
};
/** history with requests for a single request, will contain more then one entry
	when redirections are followed */
var array<RequestHistoryEntry> RequestHistory;

/** the link class to use */
var protected class<HttpLink> HttpLinkClass;
/** @ignore */
var protected HttpLink HttpLink;
/** @ignore */
var protected string inBuffer, outBuffer;
/** @ignore */
var protected bool procHeader;

/** @ingore */
var protected InternetLink.IpAddr LocalLink;
/** the port we are connected to */
var protected int BoundPort;

/** @ignore */
var protected bool FollowingRedir, RedirTrap;
/** @ignore */
var protected int CurRedir;

/** @ignore */
var protected array<string> authBasicLookup;

/** Timezone Offset, dynamically calculated from the server's time */
var protected int TZoffset;

/** @ignore */
var protected int chunkedCounter; // to count the current chunk
/** @ignore */
var protected bool bIsChunked; // if Transfer-Encoding: chunked
/** @ignore */
var protected bool bTimeout;

enum HTTPState
{
		HTTPState_Resolving,
		HTTPState_Connecting,
		HTTPState_SendingRequest,
		HTTPState_WaitingForResponse,
		HTTPState_ReceivingData,
		HTTPState_Closed,
};
/** The current state of the socket */
var HTTPState curState;

/** resolve chache entry to speed up subsequent request */
struct ResolveCacheEntry
{
	/** the hostname */
	var string Hostname;
	/** the address information */
	var InternetLink.IpAddr Address;
};
/** Resolve cache, already resolved hostnames are not looked up.
	You have to keep the actor alive in order to use this feature */
var protected array<ResolveCacheEntry> ResolveCache;
/** the hostname being resolved, used to add to the resolve cache */
var protected string ResolveHostname;

////////////////////////////////////////////////////////////////////////////////
//
//   Delegates
//
////////////////////////////////////////////////////////////////////////////////

/**
	Will be called when the return code has been received; This is the first
	function called after the request has been send.
*/
delegate OnReturnCode(int ReturnCode, string ReturnMessage, string HttpVer);

/**
	Will be called in case of an internal error.
*/
delegate OnError(string ErrorMessage, optional string Param1, optional string Param2);

/**
	Will be called when the host name is resolved. <br />
	Return true to continue, or false to abort.
*/
delegate bool OnResolved(string hostname, InternetLink.IpAddr Addr)
{
	return true;
}

/** Called when the resolved failed, hostname is the hostname that could not be resolved */
delegate OnResolveFailed(string hostname);

/**
	called when the connection has timed out (e.g. open() failed after a set time)
*/
delegate OnConnectionTimeout();

/**
	Will be called when the operation was completed successfully. <br />
	It won't be called when an time out occured.
*/
delegate OnComplete();

/**
	Called before the connection is established
*/
delegate OnPreConnect();

/**
	Called when Open() fails
*/
delegate OnConnectError();

/**
	Called before the redirection is followed, return false to prevernt following
	the	redirection
*/
delegate bool OnFollowRedirect(string NewLocation)
{
	return true;
}

////////////////////////////////////////////////////////////////////////////////
//
//   Public functions
//
////////////////////////////////////////////////////////////////////////////////

/**
	This will perform a simple HTTP GET request. This will be the most commonly
	used function to retrieve a document from a webserver. The location is just
	like the location you would use in your webbrowser.
*/
function bool get(string location)
{
	return HttpRequest(location, HTTP_GET);
}

/**
	This will perform a simple HTTP POST request. If the PostData is not empty
	it will overwrite the current post data and set the content type to
	<code>application/x-www-form-urlencoded</code>.
*/
function bool post(string location, optional string PostData)
{
	if (PostData != "")
	{
		RequestData.length = 0;
		RequestData[0] = PostData;
		AddHeader("Content-Type", "application/x-www-form-urlencoded");
	}
	return HttpRequest(location, HTTP_POST);
}

/**
	Perform a HTTP POST request using an array containing the postdata.
	if the array length > 0 it will overwrite the current post data.
	It will send the post data AS IS and doesn't set the content-type. <br />
	You might want to use this function together with <code>setFormData();</code>
*/
function bool postex(string location, optional array<string> PostData)
{
	if (PostData.length > 0) RequestData = PostData;
	return HttpRequest(location, HTTP_POST);
}

/**
	Add form data (used for <code>multipart/form-data</code> instead of
	<code>application/x-www-form-urlencoded</code>). This method makes it easier
	to add form-data. It doesn't clear the previous data, it will just append it.
	Form Data gives you more control over the actual data send. Also you don't
	have to escape the data. <br />
	It will also force the content type to <code>multipart/form-data</code>.
*/
function bool setFormData(string field, array<string> data, optional string contentType, optional string contentEncoding)
{
	//TODO: implement
	return true;
}

/**
	perform a HTTP HEAD request. This will only return the headers. Use this this
	if you only want to check the file info on the server and not the whole body.
*/
function bool head(string location)
{
	return HttpRequest(location, HTTP_HEAD);
}

/**
	Add a header, case insensitive.	Set bNoReplace to false to not overwrite the old header.
	Returns true when the header has been set.
*/
function bool AddHeader(string hname, string value, optional bool bNoReplace)
{
	local int i;
	for (i = RequestHeaders.length-1; i >= 0; i--)
	{
		if (Left(RequestHeaders[i], InStr(RequestHeaders[i], ":")) ~= hname)
		{
			if (bNoReplace) return false;
			RequestHeaders.remove(i, 1);
			break;
		}
	}
	if (value == "") return false;
	RequestHeaders[RequestHeaders.length] = hname$":"@value;
	return true;
}

/**
	Remove a header, case insensitive. Returns true when the header is deleted
*/
function bool RemoveHeader(string hname)
{
	local int i;
	for (i = 0; i < RequestHeaders.length; i++)
	{
		if (Left(RequestHeaders[i], InStr(RequestHeaders[i], ":")) ~= hname)
		{
			RequestHeaders.remove(i, 1);
			return true;
		}
	}
	return false;
}

/**
	Returns the value of the requested header, or default if not found
*/
function string GetRequestHeader(string hname, optional string def)
{
	local int i, j;
	for (i = 0; i < RequestHeaders.length; i++)
	{
		j = InStr(RequestHeaders[i], ":");
		if (Left(RequestHeaders[i], j) ~= hname)
		{
			return Mid(RequestHeaders[i], j+1);
		}
	}
	return def;
}

/**
	Returns the value of the returned header, or default if not found
*/
function string GetReturnHeader(string hname, optional string def)
{
	local int i, j;
	for (i = 0; i < RequestHeaders.length; i++)
	{
		j = InStr(ReturnHeaders[i], ":");
		if (Left(ReturnHeaders[i], j) ~= hname)
		{
			return Mid(ReturnHeaders[i], j+1);
		}
	}
	return def;
}

/**
	Abort the current request, if possible
*/
function bool Abort()
{
	if (HttpLink == none) return true;
	switch (curState)
	{
		case HTTPState_Connecting:
		case HTTPState_ReceivingData: if (HttpLink.IsConnected()) return HttpLink.Close();
	}
	return false;
}

/** Set the HTTP version, if empty the default will be used.
	Returns true when the version has been updated */
function bool setHTTPversion(optional string newver)
{
	if (newver == "")
	{
		HTTPVER = default.HTTPVER;
		return true;
	}
	else if ((newver ~= "1.0") || (newver ~= "1.1"))
	{
		HTTPVER = newver;
		return true;
	}
	return false;
}

/** return thr current HTTP version setting */
function string getHTTPversion()
{
	return HTTPVER;
}

////////////////////////////////////////////////////////////////////////////////
//
//   Internal functions
//
////////////////////////////////////////////////////////////////////////////////

/**
	Start the HTTP request. Location can be a fully qualified url, or just the l
	ocation on the configured server. <br />
	This is an internal function called by the <code>get()</code>,
	<code>head()</code> and <code>post()</code> functions. If you want to support
	additional HTTP requests you should subclass this class.
*/
protected function bool HttpRequest(string location, string Method)
{
	if (curState != HTTPState_Closed)
	{
		Logf("HttpSock not closed", class'HttpUtil'.default.LOGERR, GetEnum(enum'HTTPState', curState));
		return false;
	}
	RequestHistory.length = 0;
	RequestMethod = Caps(Method);
	if (!IsSupportedMethod())
	{
		Logf("Unsupported method", class'HttpUtil'.default.LOGERR, RequestMethod);
		return false;
	}

	if (Left(location, 5) ~= "https")
	{
		Logf("Secure HTTP connections (https://) are not supported", class'HttpUtil'.default.LOGERR);
		return false;
	}

	if (Left(location, 4) ~= "http") ParseRequestUrl(location, Method);
	else if (Left(location, 1) != "/")
	{
		Logf("Unsupported location", class'HttpUtil'.default.LOGERR, location);
		return false;
	}
	else RequestLocation = location;
	if (sHostname == "")
	{
		Logf("No remote hostname", class'HttpUtil'.default.LOGERR);
		return false;
	}
	if ((iPort <= 0) || (iPort >= 65536))
	{
		Logf("Changing remote port to default (80)", class'HttpUtil'.default.LOGWARN, iPort);
		iPort = 80;
	}
	// Add default headers
	AddHeader("Host", sHostname);
	AddHeader("User-Agent", UserAgent());
	AddHeader("Connection", "close");
	AddHeader("Accept", DefaultAccept);
	if (sAuthUsername != "") AddHeader("Authorization", genBasicAuthorization(sAuthUsername, sAuthPassword));
	if ((Method ~= "POST") && (InStr(RequestLocation, "?") > -1 ))
	{
		//TODO: combine  URL options and existing post data
		RequestData.length = 1;
		Divide(RequestLocation, "?", RequestLocation, RequestData[0]);
		AddHeader("Content-Type", "application/x-www-form-urlencoded");
	}
	// start resolve
	CurRedir = 0;
	CRLF = Chr(13)$Chr(10);
	return OpenConnection();
}

/** manage logging */
protected function Logf(coerce string message, optional int level, optional coerce string Param1, optional coerce string Param2)
{
	if (level == class'HttpUtil'.default.LOGERR) OnError(Message, Param1, Param2);
	if (level <= iVerbose) class'HttpUtil'.static.Logf(Name, Message, Level, Param1, Param2);
}

/** Returns the useragent string we use */
protected function string UserAgent()
{
	return "LibHTTP/"$VERSION@"(UnrealEngine2; build "@Level.EngineVersion$"; http://wiki.beyondunreal.com/wiki/LibHTTP )";
}

/**
	Return the actual data size of a string array, it appends sizeof(CRLF) for
	each line. This is used for sending the RequestData.
*/
protected function int DataSize(out array<string> data)
{
	local int i, res, crlflen;
	res = 0;
	crlflen = Len(CRLF);
	for (i = 0; i < data.length; i++)
	{
		res += Len(data[i])+crlflen;
	}
	return res;
}

/** Returns true when the request method is supported */
protected function bool IsSupportedMethod()
{
	if (RequestMethod ~= HTTP_GET) return true;
	else if (RequestMethod ~= HTTP_HEAD) return true;
	else if (RequestMethod ~= HTTP_POST) return true;
	return false;
}

/** Parses the fully qualified URL */
protected function ParseRequestUrl(string location, string Method)
{
	local int i, j;
	location = Mid(location, InStr(location, ":")+3); // trim leading http://
	i = InStr(location, "/");
	if (i > 0)
	{
		RequestLocation = Mid(location, i);
		location = Left(location, i);
	}
	else RequestLocation = "/"; // get index
	Logf("ParseRequestUrl", class'HttpUtil'.default.LOGINFO, "RequestLocation", RequestLocation);
	i = InStr(location, "@");
	if (i > -1)
	{
		sAuthUsername = Left(location, i);
		location = Mid(location, i+1);
		j = InStr(sAuthUsername, ":");
		if (j > -1)
		{
			sAuthPassword = Mid(sAuthUsername, j+1);
			sAuthUsername = Left(sAuthUsername, j);
			Logf("ParseRequestUrl", class'HttpUtil'.default.LOGINFO, "sAuthPassword", sAuthPassword);
		}
		Logf("ParseRequestUrl", class'HttpUtil'.default.LOGINFO, "sAuthUsername", sAuthUsername);
	}
	i = InStr(location, ":");
	if (i > -1)
	{
		iPort = int(Mid(iPort, i));
		Logf("ParseRequestUrl", class'HttpUtil'.default.LOGINFO, "iPort", iPort);
		location = Left(location, i);
	}
	sHostname = location;
	Logf("ParseRequestUrl", class'HttpUtil'.default.LOGINFO, "sHostname", sHostname);
}

/** start the download */
protected function bool OpenConnection()
{
	local int i;
	i = RequestHistory.Length;
	RequestHistory.Length = i+1;
	RequestHistory[i].Hostname = sHostname;
	RequestHistory[i].Method = RequestMethod;
	RequestHistory[i].Location = RequestLocation;
	RequestHistory[i].HTTPresponse = 0; // none yet

	if (!CreateSocket()) return false;

	if (bUseProxy)
	{
		if (sProxyHost == "")
		{
			Logf("No remote hostname", class'HttpUtil'.default.LOGERR);
			return false;
		}
		if ((iProxyPort <= 0) || (iProxyPort >= 65536))
		{
			Logf("Chaning proxy port to default (80)", class'HttpUtil'.default.LOGWARN, iProxyPort);
			iProxyPort = 80;
		}
		if (!CachedResolve(sProxyHost))
		{
			curState = HTTPState_Resolving;
			ResolveHostname = sProxyHost;
			HttpLink.Resolve(sProxyHost);
		}
	}
	else {
		if (!CachedResolve(sHostname))
		{
			curState = HTTPState_Resolving;
			ResolveHostname = sHostname;
			HttpLink.Resolve(sHostname);
		}
	}
	return true;
}

/** lookup a chached resolve and connect if found */
protected function bool CachedResolve(coerce string hostname, optional bool bDontConnect)
{
	local int i;
	for (i = 0; i < ResolveCache.Length; i++)
	{
		if (ResolveCache[i].Hostname ~= hostname)
		{
			Logf("Resolve cache hit", class'HttpUtil'.default.LOGINFO, hostname, HttpLink.IpAddrToString(ResolveCache[i].Address));
			ResolveHostname = hostname;
			if (!bDontConnect) InternalResolved(ResolveCache[i].Address, true);
			return true;
		}
	}
	return false;
}

/** hostname has been resolved */
function InternalResolved( InternetLink.IpAddr Addr , optional bool bDontCache)
{
	local int i;
	Logf("Host resolved succesfully", class'HttpUtil'.default.LOGINFO, ResolveHostname);
	if (!bDontCache)
	{
		ResolveCache.Length = ResolveCache.Length+1;
		ResolveCache[ResolveCache.length-1].Hostname = ResolveHostname;
		ResolveCache[ResolveCache.length-1].Address = Addr;
	}
	LocalLink.Addr = Addr.Addr;
	if (bUseProxy) LocalLink.Port = iProxyPort;
		else LocalLink.Port = iPort;
	if (!OnResolved(ResolveHostname, Addr))
	{
		Logf("Request aborted", class'HttpUtil'.default.LOGWARN, "OnResolved() == false");
		curState = HTTPState_Closed;
		return;
	}
	if (iLocalPort > 0)
	{
		BoundPort = HttpLink.BindPort(iLocalPort, true);
		if (BoundPort != iLocalPort) Logf("Could not bind preference port", class'HttpUtil'.default.LOGWARN, iLocalPort, BoundPort);
	}
	else BoundPort = HttpLink.BindPort();

	if (BoundPort > 0) Logf("Local port succesfully bound", class'HttpUtil'.default.LOGINFO, BoundPort);
	else {
		Logf("Error binding local port", class'HttpUtil'.default.LOGERR, BoundPort );
		CloseSocket();
		return;
	}

	HttpLink.LinkMode = MODE_Text;
	HttpLink.ReceiveMode = RMODE_Event;

	OnPreConnect();
	curState = HTTPState_Connecting;
	bTimeout = false;
	SetTimer(fConnectTimout, false);
	Logf("Opening connection", class'HttpUtil'.default.LOGINFO);
	if (!HttpLink.Open(LocalLink))
	{
		Logf("Open() failed", class'HttpUtil'.default.LOGERR, HttpLink.GetLastError());
		curState = HTTPState_Closed;
		OnConnectError();
	}
}

/** will be called from HttpLink when the resolve failed */
function ResolveFailed()
{
	curState = HTTPState_Closed;
	Logf("Resolve failed", class'HttpUtil'.default.LOGERR, ResolveHostname);
	OnResolveFailed(ResolveHostname);
}

/** timer is used for the conenection timeout. */
function Timer()
{
	if (curState == HTTPState_Connecting)
	{
		bTimeout = true;
		Logf("Connection timeout", class'HttpUtil'.default.LOGERR, fConnectTimout);
		CloseSocket();
		curState = HTTPState_Closed;
		OnConnectionTimeout();
	}
}

/** will be called from HttpLink */
function Opened()
{
	local int i;
	Logf("Connection established", class'HttpUtil'.default.LOGINFO);
	curState = HTTPState_SendingRequest;
	inBuffer = ""; // clear buffer
	outBuffer = ""; // clear buffer
	if (bUseProxy) SendData(RequestMethod@"http://"$sHostname$":"$string(iPort)$RequestLocation@"HTTP/"$HTTPVER);
		else SendData(RequestMethod@RequestLocation@"HTTP/"$HTTPVER);
	if ((RequestMethod ~= HTTP_POST) || (RequestMethod ~= HTTP_PUT))
	{
		AddHeader("Content-Length", string(DataSize(RequestData)));
	}
	if (bSendCookies && (Cookies != none))
	{
		AddHeader("Cookie", Cookies.GetCookieString(sHostname, RequestLocation, now()));
	}
	for (i = 0; i < RequestHeaders.length; i++)
	{
		SendData(RequestHeaders[i]);
	}
	if ((RequestMethod ~= HTTP_POST) || (RequestMethod ~= HTTP_PUT))
	{
		SendData("");
		for (i = 0; i < RequestData.length; i++)
		{
			SendData(RequestData[i], (i == RequestData.length-1));
		}
	}
	else SendData("", true); // flush the request
	ReturnHeaders.length = 0;
	ReturnData.length = 0;
	procHeader = true;
	FollowingRedir = false;
	RedirTrap = false;
	bIsChunked = false;
	chunkedCounter = 0;
	curState = HTTPState_WaitingForResponse;
	Logf("Request send", class'HttpUtil'.default.LOGINFO);
}

/** connection closed, check for a required redirection */
function Closed()
{
	local int i;
	FollowingRedir = RedirTrap;
	if (Len(inBuffer) > 0) ProcInput(inBuffer);
	if (!FollowingRedir)
	{
		Logf("Connection closed", class'HttpUtil'.default.LOGINFO);
		curState = HTTPState_Closed;
		if (!bTimeout) OnComplete();
	}
	else {
		CurRedir++;
		if (iMaxRedir >= CurRedir) Logf("MaxRedir reached", class'HttpUtil'.default.LOGWARN, iMaxRedir, CurRedir);
		i = RequestHistory.Length;
		if (!OnFollowRedirect("http://"$sHostname$RequestLocation)) return;
		AddHeader("Referer", "http://"$RequestHistory[i].Hostname$RequestHistory[i].Location);
		OpenConnection();
	}
}

/** create the socket, if required */
function bool CreateSocket()
{
	if (HttpLink != none) return true;
	if (HttpLinkClass == none)
	{
		Logf("Error creating link class", class'HttpUtil'.default.LOGERR, HttpLinkClass);
		return false;
	}
	HttpLink = spawn(HttpLinkClass);
	HttpLink.setSocket(self);
	Logf("Socket created", class'HttpUtil'.default.LOGINFO, HttpLink);
	return true;
}

/** destroy the current socket, should only be called in case of a timeout */
function CloseSocket()
{
	if (HttpLink.IsConnected()) HttpLink.Close();
	HttpLink.Shutdown();
	HttpLink = none;
	Logf("Socket closed", class'HttpUtil'.default.LOGINFO);
}

/** called from HttpLink */
function ReceivedText( string Line )
{
	local array<string> tmp;
	local int i, datalen;

	curState = HTTPState_ReceivingData;
	if (Split(line, Chr(10), tmp) == 0) return;
	tmp[0] = inBuffer$tmp[0];
	for (i = 0; i < tmp.length-1; i++)
	{
		datalen = Len(tmp[i])+1;
		if (Right(tmp[i], 1) == Chr(13)) tmp[i] = Left(tmp[i], datalen-2); // trim trailing #13
		if (Left(tmp[i], 1) == Chr(13)) tmp[i] = Mid(tmp[i], 1); // trim leading #13
		ProcInput(tmp[i]);
		if (bIsChunked && !procHeader) chunkedCounter -= datalen; // +1 for the missing #10
	}
	if (tmp.length > 0) inBuffer = tmp[tmp.length-1];
}

/**
	Process the input
*/
protected function ProcInput(string inline)
{
	local array<string> tmp2;
	local int retc, i;
	Logf("Received data", class'HttpUtil'.default.LOGDATA, procHeader, len(inline)$"::"@inline);
	if (procHeader)
	{
		if (inline == "")
		{
			procHeader = false;
			return;
		}

		if (ReturnHeaders.length == 0)
		{
			Split(inline, " ", tmp2);
			retc = int(tmp2[1]);
			if (bFollowRedirect && ((retc == 301) || (retc == 302)) && (iMaxRedir > CurRedir))
			{
				Logf("Redirecting", class'HttpUtil'.default.LOGINFO, retc);
				FollowingRedir = true;
				RedirTrap = false;
			}
			RequestHistory[RequestHistory.Length-1].HTTPresponse = retc;
					  // code  description  http/1.0
			OnReturnCode(retc, tmp2[2], tmp2[0]);
			LastStatus = retc;
		}
		ReturnHeaders[ReturnHeaders.length] = inline;

		// if following redirection find new location
		retc = InStr(inline, ":");
		if (FollowingRedir)
		{
			if (Left(inline, retc) ~= "location")
			{
				Logf("Redirect Location", class'HttpUtil'.default.LOGINFO, inline);
				RequestLocation = class'HttpUtil'.static.Trim(Mid(inline, retc+1));
				if (RequestMethod != HTTP_GET) // redir is always a GET
				{
					Logf("Changing request method to GET", class'HttpUtil'.default.LOGWARN, RequestMethod);
					RequestMethod = HTTP_GET;
				}
				//TODO: perform more checks
				if (Left(RequestLocation, 4) ~= "http") ParseRequestUrl(RequestLocation, RequestMethod);
				AddHeader("Host", sHostname); // make sure the new host is set
				RedirTrap = true;
			}
		}
		if (bProcCookies && (Cookies != none))
		{
			if (Left(inline, retc) ~= "set-cookie")
			{
				Cookies.ParseCookieData(Mid(inline, retc+1), sHostname, RequestLocation, now(), true, TZoffset);
			}
		}
		if (Left(inline, retc) ~= "date")
		{
			// calculate timezone offset
			i = class'HttpUtil'.static.stringToTimestamp(class'HttpUtil'.static.trim(Mid(inline, retc+1)));
			Logf("Server date", class'HttpUtil'.default.LOGINFO, i);
			if (i != 0)
			{
				TZoffset = (now()-i)/3600;
				Logf("Timezone offset", class'HttpUtil'.default.LOGINFO, TZoffset);
			}
		}
		if (Left(inline, retc) ~= "transfer-encoding")
		{
			bIsChunked = InStr(Caps(inline), "CHUNKED") > -1;
			Logf("Body is chunked", class'HttpUtil'.default.LOGINFO, bIsChunked);
		}
	}
	else {
		if (bIsChunked && (chunkedCounter <= 0))
		{
			chunkedCounter = class'HttpUtil'.static.HexToDec(inline);
			Logf("Next chunk", class'HttpUtil'.default.LOGINFO, chunkedCounter);
		}
		else ReturnData[ReturnData.length] = inline;
	}
}

/**
	Send data buffered<br />
	if bFlush it will flush all remaining data (should be used for the last call)
*/
protected function SendData(string data, optional bool bFlush)
{
	if (Len(outBuffer)+len(data) > BUFFERSIZE)
	{
		HttpLink.SendText(outBuffer);
		outBuffer = "";
	}
	while (len(data) > BUFFERSIZE)
	{
		HttpLink.SendText(Left(data, BUFFERSIZE));
		data = Mid(data, BUFFERSIZE);
	}
	outBuffer = outBuffer$data$CRLF;
	if (bFlush)
	{
		HttpLink.SendText(outBuffer);
		outBuffer = "";
	}
}

/**
	Generated a basic authentication
*/
protected function string genBasicAuthorization(string Username, string Password)
{
	local array<string> res;
	if (authBasicLookup.length == 0) class'HttpUtil'.static.Base64EncodeLookupTable(authBasicLookup);
	res[0] = Username$":"$Password;
	res = class'HttpUtil'.static.Base64Encode(res, authBasicLookup);
	Logf("Base 64 encoding", class'HttpUtil'.default.LOGINFO, Username$":"$Password, res[0]);
	return "Basic"@res[0];
}

/**
	Returns the current timestamp
*/
function int now()
{
	return class'HttpUtil'.static.timestamp(Level.Year, Level.Month, Level.Day, Level.Hour, Level.Minute, Level.Second);
}

defaultproperties
{
	iVerbose=-1
	iLocalPort=0
	bFollowRedirect=true
	curState=HTTPState_Closed
	iMaxRedir=5
	HTTPVER="1.1"
	DefaultAccept="text/*"
	bSendCookies=true
	bProcCookies=true
	bUseProxy=false
	fConnectTimout=60
	HttpLinkClass=class'HttpLink'
}
