/**
	HttpUtil
	Static functions. Part of [[LibHTTP]].

	Dcoumentation and Information:
		http://wiki.beyondunreal.com/wiki/LibHTTP

	Authors:	Michiel 'El Muerte' Hendriks <elmuerte@drunksnipers.com>

	$Id: HttpUtil.uc,v 1.5 2003/07/30 19:39:34 elmuerte Exp $
*/

class HttpUtil extends Object;

/* log levels */
var const int LOGERR;
var const int LOGWARN;
var const int LOGINFO;
var const int LOGDATA;

var array<string> MonthNames;

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

	if (B64Lookup.length != 64) Base64LookupTable(B64Lookup);

	// convert string to byte array
	for (n = 0; n < indata.length; n++)
	{
		res = indata[n];
		for (i = 0; i < len(res); i++)
		{
			inp[inp.length] = Asc(Mid(res, i, 1));
		}
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
		if ((i%57)==54) 
		{
			res = "";
			for (i = 0; i < outp.length; i++)
			{
				res = res$outp[i];
			}
			result[result.length] = res;
			outp.length = 0;
		}
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

	return result;
}

/**
	Generated the base 64 lookup table
*/
static function Base64LookupTable(out array<string> LookupTable)
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