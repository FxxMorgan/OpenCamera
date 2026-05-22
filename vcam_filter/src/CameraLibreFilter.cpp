#include "CameraLibreFilter.h"
#include "CameraLibreStream.h"

CUnknown* WINAPI CameraLibreFilter::CreateInstance(LPUNKNOWN lpunk, HRESULT* phr) {
    CameraLibreFilter* pNewObject = new CameraLibreFilter(lpunk, phr);
    if (pNewObject == NULL) {
        if (phr) *phr = E_OUTOFMEMORY;
    }
    return pNewObject;
}

CameraLibreFilter::CameraLibreFilter(LPUNKNOWN lpunk, HRESULT* phr)
    : CSource(NAME("Camera Libre Virtual Cam"), lpunk, CLSID_CameraLibreVCam) {
    
    CameraLibreStream* pPin = new CameraLibreStream(phr, this, L"Capture");
    if (pPin == NULL) {
        if (phr) *phr = E_OUTOFMEMORY;
    }
}

CameraLibreFilter::~CameraLibreFilter() {
}
