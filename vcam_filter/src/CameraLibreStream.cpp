#include <fstream>
#include <iomanip>
#include "CameraLibreStream.h"
#include <dvdmedia.h>
#include <cstdint>

struct SharedFrameHeader {
    int width;
    int height;
    int frameCount;
    int padding;
};

static void LogDebug(const char* format, ...) {
    char buffer[512];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    std::ofstream file("C:\\ProgramData\\CameraLibre\\filter.log", std::ios::app);
    if (file.is_open()) {
        SYSTEMTIME lt;
        GetLocalTime(&lt);
        file << "[" 
             << std::setw(2) << std::setfill('0') << lt.wHour << ":"
             << std::setw(2) << std::setfill('0') << lt.wMinute << ":"
             << std::setw(2) << std::setfill('0') << lt.wSecond << "."
             << std::setw(3) << std::setfill('0') << lt.wMilliseconds << "] "
             << buffer << "\n";
    }
}

CameraLibreStream::CameraLibreStream(HRESULT* phr, CameraLibreFilter* pParent, LPCWSTR pPinName)
    : CSourceStream(NAME("CameraLibre Capture"), phr, pParent, pPinName) {
    LogDebug("CameraLibreStream constructor called");
    // Ensure width is even for YUY2 alignment
    if (currentWidth_ % 2 != 0) {
        currentWidth_ = (currentWidth_ >> 1) << 1;
    }
    openIpcMapping();
}

CameraLibreStream::~CameraLibreStream() {
    LogDebug("CameraLibreStream destructor called");
    if (pBuf_) UnmapViewOfFile(pBuf_);
    if (hMapFile_) CloseHandle(hMapFile_);
    if (hFile_ != INVALID_HANDLE_VALUE) CloseHandle(hFile_);
}

void CameraLibreStream::openIpcMapping() {
    LogDebug("openIpcMapping() called");
    
    // Open the backing file written by camera_libre_server.exe
    hFile_ = CreateFileA(
        "C:\\ProgramData\\CameraLibre\\frame.dat",
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL);

    if (hFile_ == INVALID_HANDLE_VALUE) {
        LogDebug("CreateFileA failed to open frame.dat. Error: %lu", GetLastError());
        return;  // Server hasn't started yet — will retry in FillBuffer
    }

    LogDebug("CreateFileA successfully opened frame.dat");

    hMapFile_ = CreateFileMappingA(hFile_, NULL, PAGE_READONLY, 0, 0, NULL);
    if (!hMapFile_) {
        LogDebug("CreateFileMappingA failed. Error: %lu", GetLastError());
        CloseHandle(hFile_);
        hFile_ = INVALID_HANDLE_VALUE;
        return;
    }

    LogDebug("CreateFileMappingA successfully created mapping");

    pBuf_ = MapViewOfFile(hMapFile_, FILE_MAP_READ, 0, 0, 0);
    if (!pBuf_) {
        LogDebug("MapViewOfFile failed. Error: %lu", GetLastError());
        CloseHandle(hMapFile_); hMapFile_ = NULL;
        CloseHandle(hFile_); hFile_ = INVALID_HANDLE_VALUE;
        return;
    }

    LogDebug("MapViewOfFile successfully mapped view. IPC fully connected!");
}

STDMETHODIMP CameraLibreStream::NonDelegatingQueryInterface(REFIID riid, void** ppv) {
    if (riid == IID_IAMStreamConfig) {
        return GetInterface(static_cast<IAMStreamConfig*>(this), ppv);
    } else if (riid == IID_IKsPropertySet) {
        return GetInterface(static_cast<IKsPropertySet*>(this), ppv);
    }
    return CSourceStream::NonDelegatingQueryInterface(riid, ppv);
}

static void ConvertRGB24ToYUY2(const uint8_t* rgb, uint8_t* yuy2, int width, int height) {
    // Force even width for perfect YUY2 pairs
    int evenWidth = (width >> 1) << 1;
    for (int y = 0; y < height; ++y) {
        const uint8_t* srcRow = rgb + y * width * 3;
        uint8_t* dstRow = yuy2 + y * evenWidth * 2;
        for (int x = 0; x < evenWidth; x += 2) {
            int srcIdx1 = x * 3;
            int srcIdx2 = (x + 1) * 3;

            uint8_t r1 = srcRow[srcIdx1];
            uint8_t g1 = srcRow[srcIdx1 + 1];
            uint8_t b1 = srcRow[srcIdx1 + 2];

            uint8_t r2 = srcRow[srcIdx2];
            uint8_t g2 = srcRow[srcIdx2 + 1];
            uint8_t b2 = srcRow[srcIdx2 + 2];

            // Standard ITU-R BT.601 YUV conversion using fast integer shifts
            uint8_t y1 = static_cast<uint8_t>(((66 * r1 + 129 * g1 + 25 * b1 + 128) >> 8) + 16);
            uint8_t y2 = static_cast<uint8_t>(((66 * r2 + 129 * g2 + 25 * b2 + 128) >> 8) + 16);

            int rAvg = (r1 + r2) >> 1;
            int gAvg = (g1 + g2) >> 1;
            int bAvg = (b1 + b2) >> 1;

            uint8_t u = static_cast<uint8_t>(((-38 * rAvg - 74 * gAvg + 112 * bAvg + 128) >> 8) + 128);
            uint8_t v = static_cast<uint8_t>(((112 * rAvg - 94 * gAvg - 18 * bAvg + 128) >> 8) + 128);

            int dstIdx = x * 2;
            dstRow[dstIdx]     = y1;
            dstRow[dstIdx + 1] = u;
            dstRow[dstIdx + 2] = y2;
            dstRow[dstIdx + 3] = v;
        }
    }
}


HRESULT CameraLibreStream::FillBuffer(IMediaSample* pSamp) {
    BYTE* pData;
    pSamp->GetPointer(&pData);
    long cbData = pSamp->GetSize();
    
    if (!pBuf_) {
        LogDebug("FillBuffer: pBuf_ is null. Retrying openIpcMapping()");
        openIpcMapping();
    }

    bool hasData = false;
    static int fillCalls = 0;
    fillCalls++;

    bool isYUY2 = (*m_mt.Subtype() == MEDIASUBTYPE_YUY2);

    if (pBuf_) {
        SharedFrameHeader* header = static_cast<SharedFrameHeader*>(pBuf_);
        if (header->width == currentWidth_ && header->height == currentHeight_) {
            int expectedSize = isYUY2 ? (currentWidth_ * currentHeight_ * 2) : (currentWidth_ * currentHeight_ * 3);
            if (cbData >= expectedSize) {
                uint8_t* srcData = reinterpret_cast<uint8_t*>(header + 1);
                if (isYUY2) {
                    // YUY2 is natively top-down in DirectShow, so convert without flipping!
                    ConvertRGB24ToYUY2(srcData, pData, currentWidth_, currentHeight_);
                } else {
                    // RGB24 is bottom-up in DirectShow, so flip vertically!
                    int stride = currentWidth_ * 3;
                    for (int y = 0; y < currentHeight_; y++) {
                        memcpy(pData + (currentHeight_ - 1 - y) * stride, srcData + y * stride, stride);
                    }
                }
                hasData = true;
                if (fillCalls % 90 == 0) {
                    LogDebug("FillBuffer: successfully copied frame %d (%s)", header->frameCount, isYUY2 ? "YUY2" : "RGB24");
                }
            } else {
                if (fillCalls % 90 == 0) {
                    LogDebug("FillBuffer: buffer size mismatch (cbData=%ld, expected>=%d)", cbData, expectedSize);
                }
            }
        } else {
            if (fillCalls % 90 == 0) {
                LogDebug("FillBuffer: resolution mismatch (header=%dx%d, current=%dx%d)", header->width, header->height, currentWidth_, currentHeight_);
            }
        }
    } else {
        if (fillCalls % 90 == 0) {
            LogDebug("FillBuffer: still no IPC mapping available");
        }
    }

    if (!hasData) {
        memset(pData, 0, cbData);
    }

    CRefTime rtStart = rtLastFrame_;
    rtLastFrame_ += (REFERENCE_TIME)(10000000 / 30); // 30 FPS constant
    CRefTime rtEnd = rtLastFrame_;

    pSamp->SetTime((REFERENCE_TIME*)&rtStart, (REFERENCE_TIME*)&rtEnd);
    pSamp->SetSyncPoint(TRUE);
    return S_OK;
}

HRESULT CameraLibreStream::CheckMediaType(const CMediaType* pMediaType) {
    if (*pMediaType->FormatType() != FORMAT_VideoInfo) return E_INVALIDARG;
    if (*pMediaType->Type() != MEDIATYPE_Video) return E_INVALIDARG;
    
    const GUID* subtype = pMediaType->Subtype();
    if (*subtype != MEDIASUBTYPE_YUY2 && *subtype != MEDIASUBTYPE_RGB24) return E_INVALIDARG;

    VIDEOINFOHEADER* pvi = (VIDEOINFOHEADER*)pMediaType->Format();
    if (!pvi) return E_INVALIDARG;

    if (*subtype == MEDIASUBTYPE_YUY2) {
        // Fuerza ancho par
        if (pvi->bmiHeader.biWidth % 2 != 0) {
            LogDebug("CheckMediaType: Rejected YUY2 format because width %ld is not even", pvi->bmiHeader.biWidth);
            return E_INVALIDARG;
        }
        // Confirma que biHeight sea positivo en la estructura YUY2
        if (pvi->bmiHeader.biHeight <= 0) {
            LogDebug("CheckMediaType: Rejected YUY2 format because biHeight %ld is non-positive", pvi->bmiHeader.biHeight);
            return E_INVALIDARG;
        }
        // Verifica que biSizeImage use width * height * 2 para YUY2
        long expectedSize = pvi->bmiHeader.biWidth * pvi->bmiHeader.biHeight * 2;
        if (pvi->bmiHeader.biSizeImage < expectedSize) {
            LogDebug("CheckMediaType: Rejected YUY2 format because biSizeImage %lu < %ld", pvi->bmiHeader.biSizeImage, expectedSize);
            return E_INVALIDARG;
        }
    } else if (*subtype == MEDIASUBTYPE_RGB24) {
        long expectedSize = pvi->bmiHeader.biWidth * abs(pvi->bmiHeader.biHeight) * 3;
        if (pvi->bmiHeader.biSizeImage < expectedSize) {
            LogDebug("CheckMediaType: Rejected RGB24 format because biSizeImage %lu < %ld", pvi->bmiHeader.biSizeImage, expectedSize);
            return E_INVALIDARG;
        }
    }

    return S_OK;
}

HRESULT CameraLibreStream::GetMediaType(int iPosition, CMediaType* pmt) {
    if (iPosition < 0) return E_INVALIDARG;
    if (iPosition > 1) return VFW_S_NO_MORE_ITEMS;

    VIDEOINFOHEADER* pvi = (VIDEOINFOHEADER*)pmt->AllocFormatBuffer(sizeof(VIDEOINFOHEADER));
    if (!pvi) return E_OUTOFMEMORY;
    ZeroMemory(pvi, sizeof(VIDEOINFOHEADER));
    
    // Fuerza ancho par
    int evenWidth = (currentWidth_ >> 1) << 1;
    
    pvi->bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    pvi->bmiHeader.biWidth = evenWidth;
    pvi->bmiHeader.biPlanes = 1;
    pvi->AvgTimePerFrame = 10000000 / 30;

    pmt->SetType(&MEDIATYPE_Video);
    pmt->SetFormatType(&FORMAT_VideoInfo);
    pmt->SetTemporalCompression(FALSE);

    if (iPosition == 0) {
        // YUY2 (Preferred for WebRTC / Chromium)
        pvi->bmiHeader.biBitCount = 16;
        pvi->bmiHeader.biCompression = 0x32595559; // 'YUY2'
        
        // Confirma que biHeight sea positivo en la estructura YUY2 (uncompressed YUV is top-down by definition)
        pvi->bmiHeader.biHeight = abs(currentHeight_);
        
        // Verifica que biSizeImage use width * height * 2 para YUY2
        pvi->bmiHeader.biSizeImage = evenWidth * abs(currentHeight_) * 2;

        pmt->SetSubtype(&MEDIASUBTYPE_YUY2);
        pmt->SetSampleSize(pvi->bmiHeader.biSizeImage);
    } else {
        // RGB24 (Legacy fallback, bottom-up format)
        pvi->bmiHeader.biBitCount = 24;
        pvi->bmiHeader.biCompression = BI_RGB;
        pvi->bmiHeader.biHeight = currentHeight_;
        pvi->bmiHeader.biSizeImage = evenWidth * abs(currentHeight_) * 3;

        pmt->SetSubtype(&MEDIASUBTYPE_RGB24);
        pmt->SetSampleSize(pvi->bmiHeader.biSizeImage);
    }

    return S_OK;
}

HRESULT CameraLibreStream::DecideBufferSize(IMemAllocator* pAlloc, ALLOCATOR_PROPERTIES* pProperties) {
    CAutoLock filterLock(m_pFilter->pStateLock());
    if (!pAlloc || !pProperties) return E_POINTER;

    HRESULT hr = NOERROR;
    VIDEOINFOHEADER* pvi = (VIDEOINFOHEADER*)m_mt.Format();
    if (!pvi) return E_UNEXPECTED;

    pProperties->cBuffers = 1;

    // Verify and enforce correct buffer size for YUY2 vs RGB24
    bool isYUY2 = (*m_mt.Subtype() == MEDIASUBTYPE_YUY2);
    int evenWidth = (currentWidth_ >> 1) << 1;
    int calculatedSize = isYUY2 ? (evenWidth * abs(currentHeight_) * 2) : (evenWidth * abs(currentHeight_) * 3);

    // Enforce allocator uses exactly calculated size (width * height * 2 for YUY2)
    pProperties->cbBuffer = calculatedSize;

    ALLOCATOR_PROPERTIES Actual;
    hr = pAlloc->SetProperties(pProperties, &Actual);
    if (FAILED(hr)) return hr;
    if (Actual.cbBuffer < pProperties->cbBuffer) return E_FAIL;
    return S_OK;
}

HRESULT CameraLibreStream::SetMediaType(const CMediaType* pMediaType) {
    if (pMediaType && pMediaType->FormatType() && *pMediaType->FormatType() == FORMAT_VideoInfo) {
        VIDEOINFOHEADER* pvi = (VIDEOINFOHEADER*)pMediaType->Format();
        if (pvi) {
            const GUID* subtype = pMediaType->Subtype();
            const char* formatName = "UNKNOWN";
            if (*subtype == MEDIASUBTYPE_YUY2) formatName = "YUY2";
            else if (*subtype == MEDIASUBTYPE_RGB24) formatName = "RGB24";

            LogDebug("SetMediaType: NEGOTIATED FORMAT SUCCESS! Subtype: %s, Resolution: %ldx%ld, biSizeImage: %lu, biHeight: %ld, SampleSize: %ld", 
                     formatName, pvi->bmiHeader.biWidth, pvi->bmiHeader.biHeight, 
                     pvi->bmiHeader.biSizeImage, pvi->bmiHeader.biHeight, pMediaType->lSampleSize);
        }
    } else {
        LogDebug("SetMediaType: Negotiated media type format block missing or invalid");
    }
    return CSourceStream::SetMediaType(pMediaType);
}

HRESULT CameraLibreStream::OnThreadCreate() {
    rtLastFrame_ = 0;
    return S_OK;
}

STDMETHODIMP CameraLibreStream::SetFormat(AM_MEDIA_TYPE* pmt) { return S_OK; }

STDMETHODIMP CameraLibreStream::GetFormat(AM_MEDIA_TYPE** ppFormat) {
    if (!ppFormat) return E_POINTER;

    // Build the media type that describes our output
    CMediaType mt;
    GetMediaType(0, &mt);

    // Allocate a copy the caller can free with CoTaskMemFree
    *ppFormat = CreateMediaType(&mt);
    if (!*ppFormat) return E_OUTOFMEMORY;

    return S_OK;
}

STDMETHODIMP CameraLibreStream::GetNumberOfCapabilities(int* piCount, int* piSize) { 
    if (!piCount || !piSize) return E_POINTER;
    *piCount = 2; *piSize = sizeof(VIDEO_STREAM_CONFIG_CAPS); return S_OK; 
}

STDMETHODIMP CameraLibreStream::GetStreamCaps(int iIndex, AM_MEDIA_TYPE** ppmt, BYTE* pSCC) {
    if (iIndex < 0) return E_INVALIDARG;
    if (iIndex > 1) return S_FALSE;
    if (!ppmt || !pSCC) return E_POINTER;

    // Fill the media type
    CMediaType mt;
    GetMediaType(iIndex, &mt);
    *ppmt = CreateMediaType(&mt);
    if (!*ppmt) return E_OUTOFMEMORY;

    // Fill the capabilities structure
    VIDEO_STREAM_CONFIG_CAPS* pCaps = reinterpret_cast<VIDEO_STREAM_CONFIG_CAPS*>(pSCC);
    ZeroMemory(pCaps, sizeof(VIDEO_STREAM_CONFIG_CAPS));

    pCaps->guid = FORMAT_VideoInfo;
    pCaps->VideoStandard = 0;

    pCaps->InputSize.cx = currentWidth_;
    pCaps->InputSize.cy = currentHeight_;
    pCaps->MinCroppingSize.cx = currentWidth_;
    pCaps->MinCroppingSize.cy = currentHeight_;
    pCaps->MaxCroppingSize.cx = currentWidth_;
    pCaps->MaxCroppingSize.cy = currentHeight_;
    pCaps->CropGranularityX = 1;
    pCaps->CropGranularityY = 1;
    pCaps->CropAlignX = 0;
    pCaps->CropAlignY = 0;

    pCaps->MinOutputSize.cx = currentWidth_;
    pCaps->MinOutputSize.cy = currentHeight_;
    pCaps->MaxOutputSize.cx = currentWidth_;
    pCaps->MaxOutputSize.cy = currentHeight_;
    pCaps->OutputGranularityX = 1;
    pCaps->OutputGranularityY = 1;

    pCaps->StretchTapsX = 0;
    pCaps->StretchTapsY = 0;
    pCaps->ShrinkTapsX = 0;
    pCaps->ShrinkTapsY = 0;

    pCaps->MinFrameInterval = 333333;    // 30 fps
    pCaps->MaxFrameInterval = 10000000;  // 1 fps (max interval)
    
    int bytesPerPixel = (iIndex == 0) ? 2 : 3;
    pCaps->MinBitsPerSecond = currentWidth_ * currentHeight_ * bytesPerPixel * 8 * 1;   // 1 fps minimum
    pCaps->MaxBitsPerSecond = currentWidth_ * currentHeight_ * bytesPerPixel * 8 * 30;  // 30 fps maximum

    return S_OK;
}

STDMETHODIMP CameraLibreStream::Set(REFGUID guidPropSet, DWORD dwID, void* pInstanceData, DWORD cbInstanceData, void* pPropData, DWORD cbPropData) { return E_NOTIMPL; }

STDMETHODIMP CameraLibreStream::Get(REFGUID guidPropSet, DWORD dwPropID, void* pInstanceData, DWORD cbInstanceData, void* pPropData, DWORD cbPropData, DWORD* pcbReturned) {
    if (guidPropSet != AMPROPSETID_Pin) return E_PROP_SET_UNSUPPORTED;
    if (dwPropID != AMPROPERTY_PIN_CATEGORY) return E_PROP_ID_UNSUPPORTED;
    if (!pPropData || cbPropData < sizeof(GUID)) return E_UNEXPECTED;

    *(GUID*)pPropData = PIN_CATEGORY_CAPTURE;
    if (pcbReturned) *pcbReturned = sizeof(GUID);
    return S_OK;
}

STDMETHODIMP CameraLibreStream::QuerySupported(REFGUID guidPropSet, DWORD dwPropID, DWORD* pTypeSupport) {
    if (guidPropSet != AMPROPSETID_Pin) return E_PROP_SET_UNSUPPORTED;
    if (dwPropID != AMPROPERTY_PIN_CATEGORY) return E_PROP_ID_UNSUPPORTED;
    if (pTypeSupport) *pTypeSupport = KSPROPERTY_SUPPORT_GET;
    return S_OK;
}

