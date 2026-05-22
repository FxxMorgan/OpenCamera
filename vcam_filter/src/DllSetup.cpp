#include <streams.h>
#include <olectl.h>
#include <initguid.h>
#include "CameraLibreFilter.h"

const REGPINTYPES sudPinTypes = {
    &MEDIATYPE_Video,
    &MEDIASUBTYPE_NULL
};

const REGFILTERPINS sudPins = {
    L"Output",          // strName
    FALSE,              // bRendered
    TRUE,               // bOutput
    FALSE,              // bZero
    FALSE,              // bMany
    &CLSID_NULL,        // clsConnectsToFilter
    L"Input",           // strConnectsToPin
    1,                  // nTypes
    &sudPinTypes        // lpTypes
};

const REGFILTER2 sudFilter = {
    1,
    MERIT_NORMAL,
    1,
    &sudPins
};

CFactoryTemplate g_Templates[] = {
    {
        L"Cámara Libre Virtual Cam",
        &CLSID_CameraLibreVCam,
        CameraLibreFilter::CreateInstance,
        NULL,
        NULL // We register via AMovieDllRegisterServer2 with REGFILTER2
    }
};

int g_cTemplates = sizeof(g_Templates) / sizeof(g_Templates[0]);

STDAPI DllRegisterServer() {
    HRESULT hr = AMovieDllRegisterServer2(TRUE);
    if (FAILED(hr)) return hr;

    IFilterMapper2* pFM2 = NULL;
    hr = CoCreateInstance(CLSID_FilterMapper2, NULL, CLSCTX_INPROC_SERVER,
                          IID_IFilterMapper2, (void**)&pFM2);
    if (SUCCEEDED(hr)) {
        hr = pFM2->RegisterFilter(
            CLSID_CameraLibreVCam,
            L"Cámara Libre Virtual Cam",
            NULL,
            &CLSID_VideoInputDeviceCategory,
            L"Cámara Libre Virtual Cam",
            &sudFilter
        );
        pFM2->Release();
    }
    return hr;
}

STDAPI DllUnregisterServer() {
    HRESULT hr = AMovieDllRegisterServer2(FALSE);
    if (FAILED(hr)) return hr;

    IFilterMapper2* pFM2 = NULL;
    hr = CoCreateInstance(CLSID_FilterMapper2, NULL, CLSCTX_INPROC_SERVER,
                          IID_IFilterMapper2, (void**)&pFM2);
    if (SUCCEEDED(hr)) {
        hr = pFM2->UnregisterFilter(&CLSID_VideoInputDeviceCategory, L"Cámara Libre Virtual Cam", CLSID_CameraLibreVCam);
        pFM2->Release();
    }
    return hr;
}

extern "C" BOOL WINAPI DllEntryPoint(HINSTANCE, ULONG, LPVOID);
BOOL APIENTRY DllMain(HANDLE hModule, DWORD dwReason, LPVOID lpReserved) {
    return DllEntryPoint((HINSTANCE)(hModule), dwReason, lpReserved);
}
