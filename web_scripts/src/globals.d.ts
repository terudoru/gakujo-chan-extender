// build.ts provides this variable locally for each expression entry.
declare var __mbgEntryResult: unknown;
declare var mbgValidateImage: (blob: Blob) => Promise<{ width: number; height: number }>;

interface MbgCompressionHookFunction {
  (this: HTMLFormElement, ...args: unknown[]): void;
  __mbgFormSubmitHook?: MbgCompressionHook;
}
interface MbgCompressionHookOwner {
  submit?: MbgCompressionHookFunction;
  requestSubmit?: MbgCompressionHookFunction;
  original?: MbgCompressionHookFunction;
}
interface MbgCompressionHook {
  prototype: MbgCompressionHookOwner;
  method: 'submit' | 'requestSubmit';
  wrapper: MbgCompressionHookFunction;
  original: MbgCompressionHookFunction;
}
interface HTMLInputElement {
  __mbgPdfCompressionCancel?: () => void;
  __mbgOfficeCompressionCancel?: () => void;
  __mbgUploadCompressionPending?: number;
}

interface MbgSubmitHookEntry {
  prototype: MbgSubmitHookOwner;
  original: MbgSubmitHookFunction;
  wrapper?: MbgSubmitHookFunction;
}
interface MbgSubmitHookFunction {
  (this: HTMLFormElement): void;
  __mbgFormSubmitHook?: MbgSubmitHookEntry;
}
interface MbgSubmitHookOwner {
  submit: MbgSubmitHookFunction;
  original?: MbgSubmitHookFunction;
}
interface Window {
  __MBG_UPLOAD_COMPRESSION_ENABLED?: boolean;
  __MBG_UPLOAD_COMPRESSION_GENERATION?: number;
  __MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES?: MbgCompressionHook[];
  __MBG_DOWNLOAD_CAPTURE_VERSION?: number | null;
  __MBG_DOWNLOAD_CAPTURE_ATTACH?: (() => void) | null;
  __MBG_DOWNLOAD_CAPTURE_HANDLER?: EventListener | null;
  __MBG_DOWNLOAD_CAPTURE_SUBMIT_HANDLER?: EventListener | null;
  __MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER?: EventListener | null;
  __MBG_DOWNLOAD_CAPTURE_DOCUMENTS?: Document[];
  __MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS?: Document[];
  __MBG_DOWNLOAD_CAPTURE_SUBMIT_PROTOTYPES?: MbgSubmitHookEntry[];
  __MBG_ESTIMATE_COURSE_NAME?: (() => string) | null;
  MoreBetterGakujoDownloads: { postMessage: (message: string) => void };

  __MBG_GPA_DISPLAY_VERSION?: number;
  __MBG_UPDATE_GPA_DISPLAY?: () => void;
  __MBG_GPA_DISPLAY_TIMER?: number;
  __MBG_GPA_DISPLAY_STARTUP_TIMERS?: number[];
  __MBG_GPA_DISPLAY_INTERVAL?: number;
  __MBG_GPA_DISPLAY_OBSERVERS?: MutationObserver[];
  __MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS?: Document[];
  __MBG_GPA_LAST_REPORTED?: number;
  GakujoGpaReport?: { postMessage: (message: string) => void };

  __MBG_REPORT_SORTER_VERSION?: number;
  __MBG_REPORT_SORTER_UPDATE?: () => boolean;
  __MBG_REPORT_SORTER_INTERVAL?: number;
  __MBG_REPORT_SORTER_DID_INITIAL_SORT?: boolean;
  __MBG_MESSAGE_READER_VERSION?: number;
  __MBG_MESSAGE_READER_UPDATE?: () => boolean;
  __MBG_MESSAGE_READER_DISPOSE?: () => void;
  __MBG_MESSAGE_READER_INTERVAL?: number;
  __MBG_TIMEOUT_POPUP_WRAPPED?: boolean;
  extendSession?: () => void;

  __MBG_EXPIRED_RECOVERY?: Record<string, {target: string; at: number; attempts: number[]}>;
  __MBG_SESSION_EXTENDER_VERSION?: number;
  __MBG_SESSION_EXTENDER_INTERVAL?: number;
  __MBG_SESSION_EXTENDER_COUNT?: number;
  __MBG_SESSION_EXTENDER_URL?: string;
}

interface MbgCalendarCourse {
  title: string;
  weekday: number;
  period: number;
  location?: string;
  teacher?: string;
  officialTitle?: string;
  officialLocation?: string;
  officialDescription?: string;
  sourceDate?: string;
  termHint?: string;
  courseCode?: string;
  authoritativeTimetableCell?: boolean;
}
interface MbgCalendarHeaderMap {
  code?: number;
  title?: number;
  weekday?: number;
  period?: number;
  location?: number;
  teacher?: number;
}
interface Window {
  __MBG_LOGIN_AUTOFILL_SUBMITTED_KEY?: string;
  __MBG_2FA_AUTO_SUBMITTED_KEY?: string;
}

interface Window {
  MoreBetterGakujoDesktopZoom: { postMessage: (message: string) => void };
  __MBG_MESSAGE_FILTER_DISPOSE?: () => void;
  __MBG_LOGIN_AUTOFILL_DISABLED?: boolean;
  __MBG_LOGIN_AUTOFILL_TIMER?: number;
  __MBG_LOGIN_AUTOFILL_SUBMIT_TIMER?: number;
  __MBG_LOGIN_AUTOFILL_MONITOR?: number;
  __MBG_LOGIN_AUTOFILL_LAST_REPORT?: string;
  __MBG_LOGIN_AUTOFILL_CHALLENGE_VISIBLE?: boolean;
  __MBG_LOGIN_AUTOFILL_ASSIST_VERSION?: number;
  __MBG_2FA_AUTOFILL_DISABLED?: boolean;
  __MBG_2FA_AUTOFILL_TIMER?: number;
}

interface Window {
  __MBG_REPORT_DRAFT_DELETED_KEYS?: Record<string, boolean>;
  __MBG_REPORT_DRAFT_PENDING_CONTEXT?: { key: string };
  __MBG_REPORT_DRAFT_SAVE_TIMER?: number;
}
interface HTMLElement {
  __MBG_REPORT_DRAFT_KEY?: string;
  __MBG_REPORT_DRAFT_RETRY?: (() => void) | null;
  __MBG_REPORT_DRAFT_REPLACE?: (() => void) | null;
}

interface Window { MoreBetterGakujoLoginAutofill: { postMessage: (message: string) => void }; }

interface Window { send?: () => void; }

interface Window {
  __MBG_PAGE_ZOOM_BASE_SCALE?: number;
  __MBG_PAGE_ZOOM_ORIGIN?: { x: number | null; y: number | null };
  __MBG_PAGE_EFFECTIVE_ZOOM?: number;
  __MBG_PAGE_ZOOM_VALUE?: number;
  __MBG_SET_PAGE_ZOOM?: (zoom: number) => number;
  __MBG_PAGE_ZOOM_REAPPLY_TIMER?: number;
  __MBG_NATIVE_ZOOM_BLOCKERS_ATTACHED?: boolean;
  __MBG_PAGE_ZOOM_OBSERVER?: MutationObserver;
  __MBG_PAGE_ZOOM_VERSION?: number;
}

interface CSSStyleDeclaration { textSizeAdjust: string; }

interface Window {
  __MBG_MESSAGE_FILTER_VERSION?: number;
  __MBG_MESSAGE_FILTER_SIGNATURE?: string;
  __MBG_MESSAGE_FILTER_UPDATE?: () => boolean;
  __MBG_MESSAGE_FILTER_INTERVAL?: number;
}

interface Window {
  __MBG_AUTHENTICATED_DOWNLOAD_RESULTS?: Record<string, MbgAuthenticatedDownloadEntry>;
}

interface MbgAuthenticatedDownloadEntry {
  state: string;
  chunks?: { state: string; index: number; bodyBase64: string }[];
  resume?: (() => void) | null;
  completion?: Record<string, unknown> | null;
  cancel?: () => void;
  payload?: Record<string, unknown>;
  code?: unknown;
  errorName?: unknown;
  message?: string;
}
interface Window {
  __MBG_MESSAGE_STARS_DISPOSE?: () => void;
  chrome: { webview: { postMessage: (message: string) => void } };
}

interface Window {
  loadNextMonth?: () => void;
  loadBeforeMonth?: () => void;
}
