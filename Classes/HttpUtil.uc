/*******************************************************************************
	HttpUtil																	<br />
	Miscelaneous static functions. Part of [[LibHTTP]].							<br />
	Contains various algorithms, under which Base64 encoding and [[MD5]] hash
	generation.																	<br />
	[[MD5 ]]code by Petr Jelinek ( http://wiki.beyondunreal.com/wiki/MD5 )		<br />
																				<br />
	Dcoumentation and Information:
		http://wiki.beyondunreal.com/wiki/LibHTTP								<br />
																				<br />
	Authors:	Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;	<br />
																				<br />
	Copyright 2003, 2004 Michiel "El Muerte" Hendriks							<br />
	Released under the Lesser Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense				<br />

	<!-- $Id: HttpUtil.uc,v 1.11 2004/09/22 09:32:02 elmuerte Exp $ -->
*******************************************************************************/

class HttpUtil extends Object;

/* log levels */
var const int LOGERR;
var const int LOGWARN;
var const int LOGINFO;
var const int LOGDATA;

/** month names to use for date string generation */
var array<string> MonthNames;

/** MD5 context */
struct MD5_CTX
{
	/** state (ABCD) */
	var array<int> state;
	/** number of bits, modulo 2^64 (lsb first) */
	var array<int> count;
	/** input buffer */
	var array<byte> buffer;
};

/**
	Encode special characters, you should not use this function, it's slow and not
	secure, so try to avoid it.
	";", "/", "?", ":", "@", "&", "=", "+", ",", "$" and " "
*/
static function string RawUrlEncode(string instring)
{
	ReplaceChar(instring, ";", "%3B");
	ReplaceChar(instring, "/", "%2F");
	ReplaceChar(instring, "?", "%3F");
	ReplaceChar(instring, ":", "%3A");
	ReplaceChar(instring, "@", "%40");
	ReplaceChar(instring, "&", "%26");
	ReplaceChar(instring, "=", "%3D");
	ReplaceChar(instring, "+", "%2B");
	ReplaceChar(instring, ",", "%2C");
	ReplaceChar(instring, "$", "%24");
	ReplaceChar(instring, " ", "%20");
	return instring;
}

/**
	replace part of a string
*/
static function ReplaceChar(out string instring, string from, string to)
{
	local int i;
	local string src;
	src = instring;
	instring = "";
	i = InStr(src, from);
	while (i > -1)
	{
		instring = instring$Left(src, i)$to;
		src = Mid(src, i+Len(from));
		i = InStr(src, from);
	}
	instring = instring$src;
}

/**
	base64 encode an input array
*/
static function array<string> Base64Encode(array<string> indata, out array<string> B64Lookup)
{
	local array<string> result;
	local int i, dl, n;
	local string res;
	local array<byte> inp;
	local array<string> outp;

	if (B64Lookup.length != 64) Base64EncodeLookupTable(B64Lookup);

	// convert string to byte array
	for (n = 0; n < indata.length; n++)
	{
		res = indata[n];
		outp.length = 0;
		inp.length = 0;
		for (i = 0; i < len(res); i++)
		{
			inp[inp.length] = Asc(Mid(res, i, 1));
		}

		dl = inp.length;
		// fix byte array
		if ((dl%3) == 1)
		{
			inp[inp.length] = 0;
			inp[inp.length] = 0;
		}
		if ((dl%3) == 2)
		{
			inp[inp.length] = 0;
		}
		i = 0;
		while (i < dl)
		{
			outp[outp.length] = B64Lookup[(inp[i] >> 2)];
			outp[outp.length] = B64Lookup[((inp[i]&3)<<4) | (inp[i+1]>>4)];
			outp[outp.length] = B64Lookup[((inp[i+1]&15)<<2) | (inp[i+2]>>6)];
			outp[outp.length] = B64Lookup[(inp[i+2]&63)];
			i += 3;
		}
		// pad result
		if ((dl%3) == 1)
		{
			outp[outp.length-1] = "=";
			outp[outp.length-2] = "=";
		}
		if ((dl%3) == 2)
		{
			outp[outp.length-1] = "=";
		}

		res = "";
		for (i = 0; i < outp.length; i++)
		{
			res = res$outp[i];
		}
		result[result.length] = res;
	}

	return result;
}

/**
	Decode a base64 encoded string
*/
static function array<string> Base64Decode(array<string> indata)
{
	local array<string> result;
	local int i, dl, n, padded;
	local string res;
	local array<byte> inp;
	local array<string> outp;

	// convert string to byte array
	for (n = 0; n < indata.length; n++)
	{
		res = indata[n];
		outp.length = 0;
		inp.length = 0;
		padded = 0;
		for (i = 0; i < len(res); i++)
		{
			dl = Asc(Mid(res, i, 1));
			// convert base64 ascii to base64 index
			if ((dl >= 65) && (dl <= 90)) dl -= 65; // cap alpha
			else if ((dl >= 97) && (dl <= 122)) dl -= 71; // low alpha
			else if ((dl >= 48) && (dl <= 57)) dl += 4; // digits
			else if (dl == 43) dl = 62;
			else if (dl == 47) dl = 63;
			else if (dl == 61) padded++;
			inp[inp.length] = dl;
		}

		dl = inp.length;
		i = 0;
		while (i < dl)
		{
			outp[outp.length] = Chr((inp[i] << 2) | (inp[i+1] >> 4));
			outp[outp.length] = Chr(((inp[i+1]&15)<<4) | (inp[i+2]>>2));
			outp[outp.length] = Chr(((inp[i+2]&3)<<6) | (inp[i+3]));
			i += 4;
		}
		outp.length = outp.length-padded;

		res = "";
		for (i = 0; i < outp.length; i++)
		{
			res = res$outp[i];
		}
		result[result.length] = res;
	}

	return result;
}

/**
	Generate the base 64 encode lookup table
*/
static function Base64EncodeLookupTable(out array<string> LookupTable)
{
	local int i;
	for (i = 0; i < 26; i++)
	{
		LookupTable[i] = Chr(i+65);
	}
	for (i = 0; i < 26; i++)
	{
		LookupTable[i+26] = Chr(i+97);
	}
	for (i = 0; i < 10; i++)
	{
		LookupTable[i+52] = Chr(i+48);
	}
	LookupTable[62] = "+";
	LookupTable[63] = "/";
}

/**
	Create a UNIX timestamp
*/
static final function int timestamp(int year, int mon, int day, int hour, int min, int sec)
{
	mon -= 2;
	if (mon <= 0) {	/* 1..12 -> 11,12,1..10 */
		mon += 12;	/* Puts Feb last since it has leap day */
		year -= 1;
	}
	return (((
	    (year/4 - year/100 + year/400 + 367*mon/12 + day) +
	      year*365 - 719499
	    )*24 + (hour-1) /* now have hours */
	   )*60 + min  /* now have minutes */
	  )*60 + sec; /* finally seconds */
}

/**
	Parse a string to a timestamp
	The date string is formatted as: Wdy, DD-Mon-YYYY HH:MM:SS GMT
	TZoffset is the local offset to GMT
*/
static final function int stringToTimestamp(string datestring, optional int TZoffset)
{
	local array<string> data, datePart, timePart;
	local int i;
	split(datestring, " ", data);
	if (data.length == 6) // date is in spaced format
	{
		data[1] = data[1]$"-"$data[2]$"-"$data[3];
		data[2] = data[4];
		data[3] = data[5];
		data.length = 4;
	}
	if (data.length == 4)
	{
		if (split(data[1], "-", datePart) != 3) return 0;
		if (split(data[2], ":", timePart) != 3) return 0;
		// find month offset
		for (i = 1; i < default.MonthNames.length; i++)
		{
			if (default.MonthNames[i] ~= datePart[1])
			{
				datePart[1] = string(i);
				break;
			}
		}
		if (Len(datePart[2]) == 2) datePart[2] = "20"$datePart[2];
		return timestamp(int(datePart[2]), int(datePart[1]), int(datePart[0]), int(timePart[0])+TZoffset+TZtoOffset(data[3]), int(timePart[1]), int(timePart[2]));
	}
	return 0;
}

/**
	Converts a timezone to an offset
*/
static final function int TZtoOffset(string TZ)
{
	if (TZ ~= "GMT") return 0;
	else if (TZ ~= "CET") return 1;
	else if (TZ ~= "CEST") return 2;
	return int(tz);

}

/**	Trim leading and trailing spaces */
static final function string Trim(coerce string S)
{
	while (Left(S, 1) == " ") S = Right(S, Len(S) - 1);
		while (Right(S, 1) == " ") S = Left(S, Len(S) - 1);
	return S;
}

/** Write a log entry */
static final function Logf(name Comp, coerce string message, optional int level, optional coerce string Param1, optional coerce string Param2)
{
	message = message@chr(9)@param1@chr(9)@Param2;
	if (Len(message) > 512) message = Left(message, 512)@"..."; // trim message (crash protection)
	Log(Comp$"["$level$"] :"@message, 'LibHTTP');
}

/** get the dirname of a filename, with traling slash */
static final function string dirname(string filename)
{
	local array<string> parts;
	local int i;
	split(filename, "/", parts);
	filename = "";
	for (i = 0; i < parts.length-1; i++)
	{
		filename = filename$parts[i]$"/";
	}
	return filename;
}

/** get the base filename */
static final function string basename(string filename)
{
	local array<string> parts;
	if (split(filename, "/", parts) > 0) return parts[parts.length-1];
	return filename;
}

/** convert a hexadecimal number to the integer counterpart */
static final function int HexToDec(string hexcode)
{
	local int res, i, cur;

	res = 0;
	hexcode = Caps(hexcode);
	for (i = 0; i < len(hexcode); i++)
	{
		cur = Asc(Mid(hexcode, i, 1));
		if (cur == 32) return res;
		cur -= 48; // 0 = ascii 30
		if (cur > 9) cur -= 7;
		if ((cur > 15) || (cur < 0)) return -1; // not possible
		res = res << 4;
		res += cur;
	}
	return res;
}

/** return the description of a HTTP response code*/
static final function string HTTPResponseCode(int code)
{
	switch (code)
	{
		case 100: return "continue";
		case 101: return "Switching Protocols";
		case 200: return "OK";
		case 201: return "Created";
		case 202: return "Accepted";
		case 203: return "Non-Authoritative Information";
		case 204: return "No Content";
		case 205: return "Reset Content";
		case 206: return "Partial Content";
		case 300: return "Multiple Choices";
		case 301: return "Moved Permanently";
		case 302: return "Found";
		case 303: return "See Other";
		case 304: return "Not Modified";
		case 305: return "Use Proxy";
		case 307: return "Temporary Redirect";
		case 400: return "Bad Request";
		case 401: return "Unauthorized";
		case 402: return "Payment Required";
		case 403: return "Forbidden";
		case 404: return "Not Found";
		case 405: return "Method Not Allowed";
		case 406: return "Not Acceptable";
		case 407: return "Proxy Authentication Required";
		case 408: return "Request Time-out";
		case 409: return "Conflict";
		case 410: return "Gone";
		case 411: return "Length Required";
		case 412: return "Precondition Failed";
		case 413: return "Request Entity Too Large";
		case 414: return "Request-URI Too Large";
		case 415: return "Unsupported Media Type";
		case 416: return "Requested range not satisfiable";
		case 417: return "Expectation Failed";
		case 500: return "Internal Server Error";
		case 501: return "Not Implemented";
		case 502: return "Bad Gateway";
		case 503: return "Service Unavailable";
		case 504: return "Gateway Time-out";
	}
	return "";
}

/**
	Split a string with quotes, quotes may appear anywhere in the string, escape
	the quote char with a \ to use a literal. <br />
	Qoutes are removed from the result, and escaped quotes are used as normal
	quotes.
*/
static function int AdvSplit(string input, string delim, out array<string> elm, optional string quoteChar)
{
	local int di, qi;
	local int delimlen, quotelen;
	local string tmp;

	// if quotechar is empty use the faster split method
	if (quoteChar == "") return Split(input, delim, elm);

	delimlen = Len(delim);
	quotelen = Len(quoteChar);
	ReplaceChar(input, "\\"$quoteChar, chr(1)); // replace escaped quotes
	while (Len(input) > 0)
	{
		di = InStr(input, delim);
		qi = InStr(input, quoteChar);

		if (di == -1 && qi == -1) // neither found
		{
			ReplaceChar(input, chr(1), quoteChar);
			elm[elm.length] = input;
			input = "";
		}
		else if ((di < qi) && (di != -1) || (qi == -1)) // delim before a quotechar
		{
			tmp = Left(input, di);
			ReplaceChar(tmp, chr(1), quoteChar);
			elm[elm.length] = tmp;
			input = Mid(input, di+delimlen);
		}
		else {
			tmp = "";
			// everything before the quote
			if (qi > 0)	tmp = Left(input, qi);
			input = mid(input, qi+quotelen);
			// up to the next quote
			qi = InStr(input, quoteChar);
			if (qi == -1) qi = Len(input);
			tmp = tmp$Left(input, qi);
			input = mid(input, qi+quotelen);
			// everything after the quote till delim
			di = InStr(input, delim);
			if (di > -1)
			{
				tmp = tmp$Left(input, di);
				input = mid(input, di+delimlen);
			}
			ReplaceChar(tmp, chr(1), quoteChar);
			elm[elm.length] = tmp;
		}
	}
	return elm.length;
}

/*
	UnrealScript MD5 routine by Petr Jelinek (PJMODOS)
	http://wiki.beyondunreal.com/wiki/MD5
	Code used for the digest authentication method.
	One change has been made: the md5 returned is lowercase
*/

/** return the MD5 of the input string */
static function string MD5String (string str)
{
	local MD5_CTX context;
	local array<byte> digest;
	local string Hex;
	local int i;

	MD5Init (context);
	MD5Update (context, str, Len(str));
	digest.Length = 16;
	MD5Final (digest, context);

	for (i = 0; i < 16; i++)
		Hex = Hex $ DecToHex(digest[i], 1);

	return Hex;
}

/** initialize the MD5 context */
static final function MD5Init(out MD5_CTX context)
{
	context.count.Length = 2;
	context.count[0] = 0;
	context.count[1] = 0;
	context.state.Length = 4;
	context.state[0] = 0x67452301;
	context.state[1] = 0xefcdab89;
	context.state[2] = 0x98badcfe;
	context.state[3] = 0x10325476;
	context.buffer.Length = 64;
}

static final function MD5Transform(out array<int> Buf, array<byte> block)
{
	local int A,B,C,D;
	local array<int> x;

	A = Buf[0];
	B = Buf[1];
	C = Buf[2];
	D = Buf[3];

	x.Length = 16;

	MD5Decode (x, block, 64);

	/* Round 1 */
	FF (a, b, c, d, x[ 0],  7, 0xd76aa478); /* 1 */
	FF (d, a, b, c, x[ 1], 12, 0xe8c7b756); /* 2 */
	FF (c, d, a, b, x[ 2], 17, 0x242070db); /* 3 */
	FF (b, c, d, a, x[ 3], 22, 0xc1bdceee); /* 4 */
	FF (a, b, c, d, x[ 4],  7, 0xf57c0faf); /* 5 */
	FF (d, a, b, c, x[ 5], 12, 0x4787c62a); /* 6 */
	FF (c, d, a, b, x[ 6], 17, 0xa8304613); /* 7 */
	FF (b, c, d, a, x[ 7], 22, 0xfd469501); /* 8 */
	FF (a, b, c, d, x[ 8],  7, 0x698098d8); /* 9 */
	FF (d, a, b, c, x[ 9], 12, 0x8b44f7af); /* 10 */
	FF (c, d, a, b, x[10], 17, 0xffff5bb1); /* 11 */
	FF (b, c, d, a, x[11], 22, 0x895cd7be); /* 12 */
	FF (a, b, c, d, x[12],  7, 0x6b901122); /* 13 */
	FF (d, a, b, c, x[13], 12, 0xfd987193); /* 14 */
	FF (c, d, a, b, x[14], 17, 0xa679438e); /* 15 */
	FF (b, c, d, a, x[15], 22, 0x49b40821); /* 16 */

	/* Round 2 */
	GG (a, b, c, d, x[ 1],  5, 0xf61e2562); /* 17 */
	GG (d, a, b, c, x[ 6],  9, 0xc040b340); /* 18 */
	GG (c, d, a, b, x[11], 14, 0x265e5a51); /* 19 */
	GG (b, c, d, a, x[ 0], 20, 0xe9b6c7aa); /* 20 */
	GG (a, b, c, d, x[ 5],  5, 0xd62f105d); /* 21 */
	GG (d, a, b, c, x[10],  9,  0x2441453); /* 22 */
	GG (c, d, a, b, x[15], 14, 0xd8a1e681); /* 23 */
	GG (b, c, d, a, x[ 4], 20, 0xe7d3fbc8); /* 24 */
	GG (a, b, c, d, x[ 9],  5, 0x21e1cde6); /* 25 */
	GG (d, a, b, c, x[14],  9, 0xc33707d6); /* 26 */
	GG (c, d, a, b, x[ 3], 14, 0xf4d50d87); /* 27 */
	GG (b, c, d, a, x[ 8], 20, 0x455a14ed); /* 28 */
	GG (a, b, c, d, x[13],  5, 0xa9e3e905); /* 29 */
	GG (d, a, b, c, x[ 2],  9, 0xfcefa3f8); /* 30 */
	GG (c, d, a, b, x[ 7], 14, 0x676f02d9); /* 31 */
	GG (b, c, d, a, x[12], 20, 0x8d2a4c8a); /* 32 */

	/* Round 3 */
	HH (a, b, c, d, x[ 5],  4, 0xfffa3942); /* 33 */
	HH (d, a, b, c, x[ 8], 11, 0x8771f681); /* 34 */
	HH (c, d, a, b, x[11], 16, 0x6d9d6122); /* 35 */
	HH (b, c, d, a, x[14], 23, 0xfde5380c); /* 36 */
	HH (a, b, c, d, x[ 1],  4, 0xa4beea44); /* 37 */
	HH (d, a, b, c, x[ 4], 11, 0x4bdecfa9); /* 38 */
	HH (c, d, a, b, x[ 7], 16, 0xf6bb4b60); /* 39 */
	HH (b, c, d, a, x[10], 23, 0xbebfbc70); /* 40 */
	HH (a, b, c, d, x[13],  4, 0x289b7ec6); /* 41 */
	HH (d, a, b, c, x[ 0], 11, 0xeaa127fa); /* 42 */
	HH (c, d, a, b, x[ 3], 16, 0xd4ef3085); /* 43 */
	HH (b, c, d, a, x[ 6], 23,  0x4881d05); /* 44 */
	HH (a, b, c, d, x[ 9],  4, 0xd9d4d039); /* 45 */
	HH (d, a, b, c, x[12], 11, 0xe6db99e5); /* 46 */
	HH (c, d, a, b, x[15], 16, 0x1fa27cf8); /* 47 */
	HH (b, c, d, a, x[ 2], 23, 0xc4ac5665); /* 48 */

	/* Round 4 */
	II (a, b, c, d, x[ 0],  6, 0xf4292244); /* 49 */
	II (d, a, b, c, x[ 7], 10, 0x432aff97); /* 50 */
	II (c, d, a, b, x[14], 15, 0xab9423a7); /* 51 */
	II (b, c, d, a, x[ 5], 21, 0xfc93a039); /* 52 */
	II (a, b, c, d, x[12],  6, 0x655b59c3); /* 53 */
	II (d, a, b, c, x[ 3], 10, 0x8f0ccc92); /* 54 */
	II (c, d, a, b, x[10], 15, 0xffeff47d); /* 55 */
	II (b, c, d, a, x[ 1], 21, 0x85845dd1); /* 56 */
	II (a, b, c, d, x[ 8],  6, 0x6fa87e4f); /* 57 */
	II (d, a, b, c, x[15], 10, 0xfe2ce6e0); /* 58 */
	II (c, d, a, b, x[ 6], 15, 0xa3014314); /* 59 */
	II (b, c, d, a, x[13], 21, 0x4e0811a1); /* 60 */
	II (a, b, c, d, x[ 4],  6, 0xf7537e82); /* 61 */
	II (d, a, b, c, x[11], 10, 0xbd3af235); /* 62 */
	II (c, d, a, b, x[ 2], 15, 0x2ad7d2bb); /* 63 */
	II (b, c, d, a, x[ 9], 21, 0xeb86d391); /* 64 */

	Buf[0] += A;
	Buf[1] += B;
	Buf[2] += C;
	Buf[3] += D;
}

/** update MD5 context */
static final function MD5Update(out MD5_CTX Context, string Data, int inputLen)
{
	local int i, index, partlen;
	local array<byte> tmpbuf;

	tmpbuf.Length = 64;
	index = ((context.count[0] >>> 3) & 0x3F);
	if ((context.count[0] += (inputLen << 3)) < (inputLen << 3))
		context.count[1]++;
	context.count[1] += (inputLen >>> 29);
	partLen = 64 - index;

	if (inputLen >= partLen)
	{
		MD5Move(Data, 0, context.buffer, index, partLen);
		MD5Transform (context.state, context.buffer);
		for (i = partLen; i + 63 < inputLen; i += 64)
		{
			MD5Move(Data, i, tmpbuf, 0, 64);
			MD5Transform (context.state, tmpbuf);
		}
		index = 0;
	}
	else
		i = 0;

	MD5Move(Data, i, context.buffer, index, inputLen-i);
}

/** finalize the MD5 context */
static final function MD5Final (out array<byte> digest, out MD5_CTX context)
{
	local array<byte> bits;
	local int i, index, padLen;
	local string strbits;
	local string PADDING;

	PADDING = chr(0x80);
	for (i = 1; i < 64; i++)
		PADDING = PADDING$chr(0);

	MD5Encode (bits, context.count, 8);

	index = ((context.count[0] >>> 3) & 0x3f);
	if (index < 56)
		padLen = (56 - index);
	else
		padLen = (120 - index);
	MD5Update (context, PADDING, padLen);
	strbits = "";
	for (i=0;i<8;i++)
		strbits = strbits$Chr(bits[i]);
	MD5Update (context, strbits, 8);
	MD5Encode (digest, context.state, 16);

	for (i = 0; i < 64; i++)
	{
		context.buffer[i] = 0;
	}
}

static final function MD5Encode (out array<byte> output, array<int> input, int len)
{
	local int i, j;

	i = 0;
	for (j = 0; j < len; j += 4)
	{
		output[j] = (input[i] & 0xff);
		output[j+1] = ((input[i] >> 8) & 0xff);
		output[j+2] = ((input[i] >> 16) & 0xff);
		output[j+3] = ((input[i] >> 24) & 0xff);
		i++;
	}
}


static final function MD5Decode(out array<int> output, array<byte> input, int len)
{
	local int i, j;

	i = 0;
	for (j = 0; j < len; j += 4)
	{
		output[i] = ((input[j]) | (int(input[j+1]) << 8) | (int(input[j+2]) << 16) | (int(input[j+3]) << 24));
		i++;
	}
}


static final function MD5Move(string src, int srcindex, out array<byte> buffer, int bufindex, int len)
{
	local int i,j;

	j = bufindex;
	for (i = srcindex; i < srcindex+len; i++)
	{
		buffer[j] = Asc(Mid(src, i, 1));
		j++;
		if (j == 64)
			break;
	}
}


static final function int ROTATE_LEFT (int x, int n)
{
	return (((x) << (n)) | ((x) >>> (32-(n))));
}

static final function int F (int x, int y, int z)
{
	return (((x) & (y)) | ((~x) & (z)));
}

static final function int G (int x, int y, int z)
{
	return ((x & z) | (y & (~z)));
}

static final function int H (int x, int y, int z)
{
	return (x ^ y ^ z);
}

static final function int I (int x, int y, int z)
{
	return (y ^ (x | (~z)));
}

static final function FF(out int a, int b, int c, int d, int x, int s, int ac)
{
	a += F(b, c, d) + x + ac;
	a = ROTATE_LEFT (a, s);
	a += b;
}

static final function GG(out int a, int b, int c, int d, int x, int s, int ac)
{
	a += G(b, c, d) + x + ac;
	a = rotate_left (a, s) +b;
}

static final function HH(out int a, int b, int c, int d, int x, int s, int ac)
{
	a += H(b, c, d) + x + ac;
	a = rotate_left (a, s) +b;
}

static final function II(out int a, int b, int c, int d, int x, int s, int ac)
{
	a += I(b, c, d) + x + ac;
	a = rotate_left (a, s) +b;
}

static final function string DecToHex(int dec, int size)
{
	const hex = "0123456789abcdef";
	local string s;
	local int i;

	for (i = 0; i < size*2; i++)
	{
		s = mid(hex, dec & 0xf, 1) $ s;
		dec = dec >>> 4;
	}

	return s;
}

defaultproperties
{
	LOGERR=0
	LOGWARN=1
	LOGINFO=2
	LOGDATA=3

	MonthNames[1]="Jan"
	MonthNames[2]="Feb"
	MonthNames[3]="Mar"
	MonthNames[4]="Apr"
	MonthNames[5]="May"
	MonthNames[6]="Jun"
	MonthNames[7]="Jul"
	MonthNames[8]="Aug"
	MonthNames[9]="Sep"
	MonthNames[10]="Oct"
	MonthNames[11]="Nov"
	MonthNames[12]="Dec"
}
