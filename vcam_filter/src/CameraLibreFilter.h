#pragma once
#include <streams.h>
#include <initguid.h>

// {83C90297-76E0-4DE0-9E11-2AC4F8EC32F4}
DEFINE_GUID(CLSID_CameraLibreVCam, 
0x83c90297, 0x76e0, 0x4de0, 0x9e, 0x11, 0x2a, 0xc4, 0xf8, 0xec, 0x32, 0xf4);

class CameraLibreFilter : public CSource {
public:
    static CUnknown* WINAPI CreateInstance(LPUNKNOWN lpunk, HRESULT* phr);
    
private:
    CameraLibreFilter(LPUNKNOWN lpunk, HRESULT* phr);
    ~CameraLibreFilter();
};
