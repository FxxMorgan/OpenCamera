//------------------------------------------------------------------------------
// File: Streams.h
//
// Desc: DirectShow base classes - defines overall streams architecture.
//
// Copyright (c) 1992-2001 Microsoft Corporation.  All rights reserved.
//------------------------------------------------------------------------------


#ifndef __STREAMS__
#define __STREAMS__

#ifndef _MSC_VER
    #ifndef AM_NOVTABLE
        #define AM_NOVTABLE
    #endif
    #ifndef __in
        #define __in
    #endif
    #ifndef __out
        #define __out
    #endif
    #ifndef __inout
        #define __inout
    #endif
    #ifndef __in_opt
        #define __in_opt
    #endif
    #ifndef __out_opt
        #define __out_opt
    #endif
    #ifndef __inout_opt
        #define __inout_opt
    #endif
    #ifndef __deref_in
        #define __deref_in
    #endif
    #ifndef __deref_out
        #define __deref_out
    #endif
    #ifndef __deref_out_opt
        #define __deref_out_opt
    #endif
    #ifndef __deref_out_range
        #define __deref_out_range(x, y)
    #endif
    #ifndef __out_range
        #define __out_range(x, y)
    #endif
    #ifndef __deref_inout_opt
        #define __deref_inout_opt
    #endif
    #ifndef __in_ecount
        #define __in_ecount(x)
    #endif
    #ifndef __out_ecount
        #define __out_ecount(x)
    #endif
    #ifndef __in_bcount
        #define __in_bcount(x)
    #endif
    #ifndef __out_bcount
        #define __out_bcount(x)
    #endif
    #ifndef __out_bcount_opt
        #define __out_bcount_opt(x)
    #endif
    #ifndef __out_ecount_part
        #define __out_ecount_part(x,y)
    #endif
    #ifndef __in_ecount_opt
        #define __in_ecount_opt(x)
    #endif
    #ifndef __out_ecount_opt
        #define __out_ecount_opt(x)
    #endif
    #ifndef __in_bcount_opt
        #define __in_bcount_opt(x)
    #endif
    #ifndef __out_bcount_part
        #define __out_bcount_part(x,y)
    #endif
    #ifndef __in_ecount_helper
        #define __in_ecount_helper(x)
    #endif
    #ifndef __out_ecount_helper
        #define __out_ecount_helper(x)
    #endif
    #ifndef __inout_ecount
        #define __inout_ecount(x)
    #endif
    #ifndef __inout_bcount
        #define __inout_bcount(x)
    #endif
    #ifndef __inout_ecount_opt
        #define __inout_ecount_opt(x)
    #endif
    #ifndef __inout_bcount_opt
        #define __inout_bcount_opt(x)
    #endif
    #ifndef __field_ecount_opt
        #define __field_ecount_opt(x)
    #endif
    #ifndef __self
        #define __self
    #endif
    #ifndef __callback
        #define __callback
    #endif
    #ifndef __format_string
        #define __format_string
    #endif
    #ifndef __blocksOn
        #define __blocksOn
    #endif
    #ifndef __controlEntry
        #define __controlEntry
    #endif
    #ifndef __post
        #define __post
    #endif
    #ifndef __pre
        #define __pre
    #endif
    #ifndef __success
        #define __success(x)
    #endif
    #ifndef __checkReturn
        #define __checkReturn
    #endif
    #ifndef __typefix
        #define __typefix
    #endif
    #ifndef __override
        #define __override
    #endif
    #ifndef __fallthrough
        #define __fallthrough
    #endif
    #ifndef __analysis_assume
        #define __analysis_assume(x)
    #endif
#endif

#ifdef	_MSC_VER
// disable some level-4 warnings, use #pragma warning(enable:###) to re-enable
#pragma warning(disable:4100) // warning C4100: unreferenced formal parameter
#pragma warning(disable:4201) // warning C4201: nonstandard extension used : nameless struct/union
#pragma warning(disable:4511) // warning C4511: copy constructor could not be generated
#pragma warning(disable:4512) // warning C4512: assignment operator could not be generated
#pragma warning(disable:4514) // warning C4514: "unreferenced inline function has been removed"

#if _MSC_VER>=1100
#define AM_NOVTABLE __declspec(novtable)
#else
#define AM_NOVTABLE
#endif
#endif	// MSC_VER


// Because of differences between Visual C++ and older Microsoft SDKs,
// you may have defined _DEBUG without defining DEBUG.  This logic
// ensures that both will be set if Visual C++ sets _DEBUG.
#ifdef _DEBUG
#ifndef DEBUG
#define DEBUG
#endif
#endif


#include <windows.h>
#include <windowsx.h>
#include <olectl.h>
#include <ddraw.h>
#include <mmsystem.h>


#ifndef NUMELMS
#if _WIN32_WINNT < 0x0600
   #define NUMELMS(aa) (sizeof(aa)/sizeof((aa)[0]))
#else
   #define NUMELMS(aa) ARRAYSIZE(aa)
#endif   
#endif

///////////////////////////////////////////////////////////////////////////
// The following definitions come from the Platform SDK and are required if
// the applicaiton is being compiled with the headers from Visual C++ 6.0.
/////////////////////////////////////////////////// ////////////////////////
#ifndef InterlockedExchangePointer
	#define InterlockedExchangePointer(Target, Value) \
   (PVOID)InterlockedExchange((PLONG)(Target), (LONG)(Value))
#endif

#ifndef _WAVEFORMATEXTENSIBLE_
#define _WAVEFORMATEXTENSIBLE_
typedef struct {
    WAVEFORMATEX    Format;
    union {
        WORD wValidBitsPerSample;       /* bits of precision  */
        WORD wSamplesPerBlock;          /* valid if wBitsPerSample==0 */
        WORD wReserved;                 /* If neither applies, set to zero. */
    } Samples;
    DWORD           dwChannelMask;      /* which channels are */
                                        /* present in stream  */
    GUID            SubFormat;
} WAVEFORMATEXTENSIBLE, *PWAVEFORMATEXTENSIBLE;
#endif // !_WAVEFORMATEXTENSIBLE_

#if !defined(WAVE_FORMAT_EXTENSIBLE)
#define  WAVE_FORMAT_EXTENSIBLE                 0xFFFE
#endif // !defined(WAVE_FORMAT_EXTENSIBLE)

#ifndef GetWindowLongPtr
  #define GetWindowLongPtrA   GetWindowLongA
  #define GetWindowLongPtrW   GetWindowLongW
  #ifdef UNICODE
    #define GetWindowLongPtr  GetWindowLongPtrW
  #else
    #define GetWindowLongPtr  GetWindowLongPtrA
  #endif // !UNICODE
#endif // !GetWindowLongPtr

#ifndef SetWindowLongPtr
  #define SetWindowLongPtrA   SetWindowLongA
  #define SetWindowLongPtrW   SetWindowLongW
  #ifdef UNICODE
    #define SetWindowLongPtr  SetWindowLongPtrW
  #else
    #define SetWindowLongPtr  SetWindowLongPtrA
  #endif // !UNICODE
#endif // !SetWindowLongPtr

#ifndef GWLP_WNDPROC
  #define GWLP_WNDPROC        (-4)
#endif
#ifndef GWLP_HINSTANCE
  #define GWLP_HINSTANCE      (-6)
#endif
#ifndef GWLP_HWNDPARENT
  #define GWLP_HWNDPARENT     (-8)
#endif
#ifndef GWLP_USERDATA
  #define GWLP_USERDATA       (-21)
#endif
#ifndef GWLP_ID
  #define GWLP_ID             (-12)
#endif
#ifndef DWLP_MSGRESULT
  #define DWLP_MSGRESULT  0
#endif
#ifndef DWLP_DLGPROC 
  #define DWLP_DLGPROC    DWLP_MSGRESULT + sizeof(LRESULT)
#endif
#ifndef DWLP_USER
  #define DWLP_USER       DWLP_DLGPROC + sizeof(DLGPROC)
#endif


#pragma warning(push)
#pragma warning(disable: 4312 4244)
// _GetWindowLongPtr
// Templated version of GetWindowLongPtr, to suppress spurious compiler warning.
template <class T>
T _GetWindowLongPtr(HWND hwnd, int nIndex)
{
    return (T)GetWindowLongPtr(hwnd, nIndex);
}

// _SetWindowLongPtr
// Templated version of SetWindowLongPtr, to suppress spurious compiler warning.
template <class T>
LONG_PTR _SetWindowLongPtr(HWND hwnd, int nIndex, T p)
{
    return SetWindowLongPtr(hwnd, nIndex, (LONG_PTR)p);
}
#pragma warning(pop)

///////////////////////////////////////////////////////////////////////////
// End Platform SDK definitions
///////////////////////////////////////////////////////////////////////////


#include <strmif.h>     // Generated IDL header file for streams interfaces
#include <intsafe.h>    // required by amvideo.h

#include "reftime.h"    // Helper class for REFERENCE_TIME management
#include "wxdebug.h"    // Debug support for logging and ASSERTs
#include <amvideo.h>    // ActiveMovie video interfaces and definitions
//include amaudio.h explicitly if you need it.  it requires the DX SDK.
//#include <amaudio.h>    // ActiveMovie audio interfaces and definitions
#include "wxutil.h"     // General helper classes for threads etc
#include "combase.h"    // Base COM classes to support IUnknown
#include "dllsetup.h"   // Filter registration support functions
#include "measure.h"    // Performance measurement
#include <comlite.h>    // Light weight com function prototypes

#include "cache.h"      // Simple cache container class
#include "wxlist.h"     // Non MFC generic list class
#include "msgthrd.h"	// CMsgThread
#include "mtype.h"      // Helper class for managing media types
#include "fourcc.h"     // conversions between FOURCCs and GUIDs
#include <control.h>    // generated from control.odl
#include "ctlutil.h"    // control interface utility classes
#include <evcode.h>     // event code definitions
#include "amfilter.h"   // Main streams architecture class hierachy
#include "transfrm.h"   // Generic transform filter
#include "transip.h"    // Generic transform-in-place filter
#include <uuids.h>      // declaration of type GUIDs and well-known clsids
#include "source.h"	// Generic source filter
#include "outputq.h"    // Output pin queueing
#include <errors.h>     // HRESULT status and error definitions
#include "renbase.h"    // Base class for writing ActiveX renderers
#include "winutil.h"    // Helps with filters that manage windows
#include "winctrl.h"    // Implements the IVideoWindow interface
#include "videoctl.h"   // Specifically video related classes
#include "refclock.h"	// Base clock class
#include "sysclock.h"	// System clock
#include "pstream.h"    // IPersistStream helper class
#include "vtrans.h"     // Video Transform Filter base class
#include "amextra.h"
#include "cprop.h"      // Base property page class
#include "strmctl.h"    // IAMStreamControl support
#include <edevdefs.h>   // External device control interface defines
#ifndef _MSC_VER
    #ifndef min
        #define min(a,b) (((a) < (b)) ? (a) : (b))
    #endif
    #ifndef max
        #define max(a,b) (((a) > (b)) ? (a) : (b))
    #endif
    #ifndef iMASK_COLORS
        #define iMASK_COLORS 3
    #endif
    #ifndef iPALETTE_COLORS
        #define iPALETTE_COLORS 256
    #endif
    #ifndef DIBSIZE
        #define DIBSIZE(bi) (((bi).biHeight < 0 ? -((bi).biHeight) : (bi).biHeight) * (((bi).biWidth * (bi).biBitCount + 31) & ~31) / 8)
    #endif
    #ifndef SIZE_PREHEADER
        #define SIZE_PREHEADER (FIELD_OFFSET(VIDEOINFOHEADER, bmiHeader))
    #endif
    #ifndef SIZE_MASKS
        #define SIZE_MASKS (3 * sizeof(DWORD))
    #endif
    #ifndef PALETTISED
        #define PALETTISED(pbmi) ((pbmi)->bmiHeader.biBitCount <= 8)
    #endif
    #ifndef TRUECOLOR
        #define TRUECOLOR(pbmi) ((TRUECOLORINFO *)(((LPBYTE)&((pbmi)->bmiHeader)) + (pbmi)->bmiHeader.biSize))
    #endif
    #ifndef COLORS
        #define COLORS(pbmi) ((RGBQUAD *)(((LPBYTE)&((pbmi)->bmiHeader)) + (pbmi)->bmiHeader.biSize))
    #endif
    #ifndef __control_entrypoint
        #define __control_entrypoint(x)
    #endif
    #ifndef HEADER
        #define HEADER(pVideoInfo) (&(((VIDEOINFOHEADER *)(pVideoInfo))->bmiHeader))
    #endif
    #ifndef DIBWIDTHBYTES
        #define DIBWIDTHBYTES(bi) (DWORD)((((bi).biWidth * (bi).biBitCount + 31) & ~31) / 8)
    #endif
    #ifdef __cplusplus
    extern "C" {
    #endif
    STDAPI_(BOOL) ContainsPalette(const VIDEOINFOHEADER *pVideoInfo);
    STDAPI_(const RGBQUAD *) GetBitmapPalette(const VIDEOINFOHEADER *pVideoInfo);
    #ifdef __cplusplus
    }
    #endif
    #ifndef SIZE_PALETTE
        #define SIZE_PALETTE (256 * sizeof(RGBQUAD))
    #endif
    #ifndef BITMASKS
        #define BITMASKS(pv) ((DWORD *)(((LPBYTE)&((pv)->bmiHeader)) + (pv)->bmiHeader.biSize))
    #endif
    #ifndef PALETTE_ENTRIES
        #define PALETTE_ENTRIES(pv) ((pv)->bmiHeader.biClrUsed ? (pv)->bmiHeader.biClrUsed : (1 << (pv)->bmiHeader.biBitCount))
    #endif
    #ifndef SIZE_VIDEOHEADER
        #define SIZE_VIDEOHEADER sizeof(VIDEOINFOHEADER)
    #endif
    #ifndef SAFE_DIBSIZE
    #ifdef __cplusplus
    extern "C" {
    #endif
    BOOL MultiplyCheckOverflow(DWORD a, DWORD b, DWORD *pab);
    #ifdef __cplusplus
    }
    #endif

    __inline HRESULT SAFE_DIBSIZE(const BITMAPINFOHEADER *pHeader, DWORD *pdwResult) {
        if (pHeader->biSizeImage == 0 && (pHeader->biCompression == BI_RGB || pHeader->biCompression == BI_BITFIELDS)) {
            DWORD dwBits = (DWORD)pHeader->biWidth * (DWORD)pHeader->biBitCount;
            DWORD dwWidthInBytes = ((dwBits + 31) & ~31) / 8;
            if (!MultiplyCheckOverflow(dwWidthInBytes, (DWORD)abs(pHeader->biHeight), pdwResult)) {
                return E_INVALIDARG;
            }
        } else {
            *pdwResult = pHeader->biSizeImage;
        }
        return S_OK;
    }
    #endif
#endif

#else
    #ifdef DEBUG
    #pragma message("STREAMS.H included TWICE")
    #endif
#endif // __STREAMS__

