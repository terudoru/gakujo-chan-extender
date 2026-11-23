#pragma once

#include <WebView2.h>
#include <oleidl.h>
#include <wil/com.h>
#include <wrl.h>

#include <functional>
#include <optional>
#include <utility>

namespace util {

class WebviewFileDropTarget final
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
          IDropTarget> {
 public:
  using LocalPoint = std::function<std::optional<POINT>(POINTL)>;

  WebviewFileDropTarget(
      wil::com_ptr<ICoreWebView2CompositionController3> controller,
      LocalPoint local_point)
      : controller_(std::move(controller)), local_point_(std::move(local_point)) {}

  IFACEMETHODIMP DragEnter(IDataObject* data, DWORD keys, POINTL screen,
                           DWORD* effect) override {
    DragLeave();
    FORMATETC format{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    if (data && (*effect & DROPEFFECT_COPY) &&
        data->QueryGetData(&format) == S_OK) {
      data_ = data;
      return DragOver(keys, screen, effect);
    }
    *effect = DROPEFFECT_NONE;
    return S_OK;
  }

  IFACEMETHODIMP DragOver(DWORD keys, POINTL screen, DWORD* effect) override {
    const auto point = data_ ? local_point_(screen) : std::nullopt;
    if (!point) {
      LeaveWebview();
      *effect = DROPEFFECT_NONE;
      return S_OK;
    }

    *effect &= DROPEFFECT_COPY;
    const HRESULT result = entered_
        ? controller_->DragOver(keys, *point, effect)
        : controller_->DragEnter(data_.get(), keys, *point, effect);
    entered_ = SUCCEEDED(result);
    *effect = entered_ ? *effect & DROPEFFECT_COPY : DROPEFFECT_NONE;
    return S_OK;
  }

  IFACEMETHODIMP DragLeave() override {
    LeaveWebview();
    data_.reset();
    return S_OK;
  }

  IFACEMETHODIMP Drop(IDataObject* data, DWORD keys, POINTL screen,
                      DWORD* effect) override {
    const auto point = entered_ ? local_point_(screen) : std::nullopt;
    if (!point || !data || !(*effect & DROPEFFECT_COPY)) {
      DragLeave();
      *effect = DROPEFFECT_NONE;
      return S_OK;
    }

    *effect &= DROPEFFECT_COPY;
    const HRESULT result = controller_->Drop(data, keys, *point, effect);
    entered_ = false;
    data_.reset();
    *effect = SUCCEEDED(result) ? *effect & DROPEFFECT_COPY : DROPEFFECT_NONE;
    return S_OK;
  }

 private:
  void LeaveWebview() {
    if (entered_) controller_->DragLeave();
    entered_ = false;
  }

  wil::com_ptr<ICoreWebView2CompositionController3> controller_;
  LocalPoint local_point_;
  wil::com_ptr<IDataObject> data_;
  bool entered_ = false;
};

}  // namespace util
