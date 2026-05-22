#pragma once
#include "CameraLibreFilter.h"
#include <windows.h>

class CameraLibreStream : public CSourceStream, public IAMStreamConfig, public IKsPropertySet {
public:
    CameraLibreStream(HRESULT* phr, CameraLibreFilter* pParent, LPCWSTR pPinName);
    ~CameraLibreStream();

    DECLARE_IUNKNOWN;

    // CSourceStream
    HRESULT FillBuffer(IMediaSample* pSamp) override;
    HRESULT DecideBufferSize(IMemAllocator* pAlloc, ALLOCATOR_PROPERTIES* pProperties) override;
    HRESULT CheckMediaType(const CMediaType* pMediaType) override;
    HRESULT GetMediaType(int iPosition, CMediaType* pmt) override;
    HRESULT SetMediaType(const CMediaType* pMediaType) override;
    HRESULT OnThreadCreate() override;

    // NonDelegatingQueryInterface for custom interfaces
    STDMETHODIMP NonDelegatingQueryInterface(REFIID riid, void** ppv) override;

    // IAMStreamConfig
    STDMETHODIMP SetFormat(AM_MEDIA_TYPE* pmt) override;
    STDMETHODIMP GetFormat(AM_MEDIA_TYPE** ppFormat) override;
    STDMETHODIMP GetNumberOfCapabilities(int* piCount, int* piSize) override;
    STDMETHODIMP GetStreamCaps(int iIndex, AM_MEDIA_TYPE** ppmt, BYTE* pSCC) override;

    // IKsPropertySet
    STDMETHODIMP Set(REFGUID guidPropSet, DWORD dwID, void* pInstanceData, DWORD cbInstanceData, void* pPropData, DWORD cbPropData) override;
    STDMETHODIMP Get(REFGUID guidPropSet, DWORD dwPropID, void* pInstanceData, DWORD cbInstanceData, void* pPropData, DWORD cbPropData, DWORD* pcbReturned) override;
    STDMETHODIMP QuerySupported(REFGUID guidPropSet, DWORD dwPropID, DWORD* pTypeSupport) override;

private:
    HANDLE hFile_    = INVALID_HANDLE_VALUE;  // Backing file for IPC
    HANDLE hMapFile_ = NULL;
    void* pBuf_ = nullptr;
    int currentWidth_ = 1280;
    int currentHeight_ = 720;
    REFERENCE_TIME rtLastFrame_ = 0;

    void openIpcMapping();
};
