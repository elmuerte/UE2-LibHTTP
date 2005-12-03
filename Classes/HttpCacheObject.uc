/*******************************************************************************
	HttpCacheObject                                                             <br />
	Physical storage of the cached data.
																				<br />
	Dcoumentation and Information:
		http://wiki.beyondunreal.com/wiki/LibHTTP                               <br />
																				<br />
	Authors:    Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;  <br />
																				<br />
	Copyright 2005 Michiel "El Muerte" Hendriks                                 <br />
	Released under the Lesser Open Unreal Mod License                           <br />
	http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense                <br />

	<!-- $Id: HttpCacheObject.uc,v 1.3 2005/08/15 08:50:14 elmuerte Exp $ -->
*******************************************************************************/

class HttpCacheObject extends Core.Object config(HttpCache) PerObjectConfig;

var config string URL;
var config int LastModification;
var config int ExpiresOn;
var config array<string> Data;
