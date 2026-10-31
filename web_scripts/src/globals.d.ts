// build.ts provides this variable locally for each expression entry.
declare var __mbgEntryResult: unknown;

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
