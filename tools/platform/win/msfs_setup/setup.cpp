// FlightSim Aide Setup for Microsoft Flight Simulator (built by build_setup.ps1).
//
// Double click: a window lists the simulators found on this PC; Install puts the package in
// each one's Community folder and adds a start-up entry to its EXE.xml; Remove undoes that.
//
// Command line (also used by tests):
//   --install | --remove            what to do (needed for the command line)
//   --sim 2024 | 2020 | all         which detected simulators (default all)
//   --community <dir> --data <dir>  one explicit target: its Community folder and the data folder
//                                   that holds EXE.xml (no detection)
//   --delete-checklists             with --remove, also delete the checklists folder
//   --root <dir>                    detect under this folder instead of %APPDATA%/%LOCALAPPDATA%
//                                   (tests): <dir>\Roaming and <dir>\Local

#define UNICODE
#define _UNICODE
#define _CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <shellapi.h>
#include <tlhelp32.h>
#include <netfw.h>
#include <objbase.h>

#include <algorithm>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

#include "payload.h"

using std::string;
using std::wstring;

namespace {

const wchar_t* kPackage = L"flightsimaide-checklists";
const wchar_t* kExeName = L"flightsim_aide_msfs.exe";
const char* kBegin = "<!-- FlightSim Aide begin -->";
const char* kEnd = "<!-- FlightSim Aide end -->";

// ---------------------------------------------------------------- small helpers

wstring env(const wchar_t* name) {
  wchar_t b[32768];
  DWORD n = GetEnvironmentVariableW(name, b, 32768);
  return n ? wstring(b, n) : wstring();
}

bool exists(const wstring& p) { return GetFileAttributesW(p.c_str()) != INVALID_FILE_ATTRIBUTES; }

bool isDir(const wstring& p) {
  DWORD a = GetFileAttributesW(p.c_str());
  return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY);
}

string toUtf8(const wstring& w) {
  if (w.empty()) return string();
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0, nullptr, nullptr);
  string s(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), &s[0], n, nullptr, nullptr);
  return s;
}

wstring fromUtf8(const string& s) {
  if (s.empty()) return wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), &w[0], n);
  return w;
}

bool readFile(const wstring& path, string& out) {
  std::ifstream f(path.c_str(), std::ios::binary);
  if (!f) return false;
  out.assign(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
  return true;
}

bool writeFile(const wstring& path, const void* data, size_t size) {
  std::ofstream f(path.c_str(), std::ios::binary | std::ios::trunc);
  if (!f) return false;
  f.write((const char*)data, (std::streamsize)size);
  return (bool)f;
}

void makeDirs(const wstring& path) {
  for (size_t i = 3; i < path.size(); ++i) {
    if (path[i] == L'\\' || path[i] == L'/') CreateDirectoryW(path.substr(0, i).c_str(), nullptr);
  }
  CreateDirectoryW(path.c_str(), nullptr);
}

bool iequals(wstring a, wstring b) {
  std::transform(a.begin(), a.end(), a.begin(), ::towlower);
  std::transform(b.begin(), b.end(), b.begin(), ::towlower);
  return a == b;
}

bool startsWithI(wstring a, wstring prefix) {
  if (a.size() < prefix.size()) return false;
  return iequals(a.substr(0, prefix.size()), prefix);
}

string xmlEscape(const string& s) {
  string o;
  for (char c : s) {
    if (c == '&') o += "&amp;";
    else if (c == '<') o += "&lt;";
    else if (c == '>') o += "&gt;";
    else o += c;
  }
  return o;
}

// ---------------------------------------------------------------- what is installed

struct Sim {
  wstring name;        // "MSFS 2024 (Steam)"
  bool untested = false;
  wstring data;        // folder with UserCfg.opt and EXE.xml
  wstring community;   // <InstalledPackagesPath>\Community
  wstring exeXml() const { return data + L"\\EXE.xml"; }
  wstring package() const { return community + L"\\" + kPackage; }
  wstring companionExe() const { return package() + L"\\companion\\" + kExeName; }
};

// The value of InstalledPackagesPath in a UserCfg.opt, or empty.
wstring installedPackagesPath(const wstring& userCfg) {
  string text;
  if (!readFile(userCfg, text)) return wstring();
  size_t at = text.find("InstalledPackagesPath");
  if (at == string::npos) return wstring();
  size_t q1 = text.find('"', at);
  size_t eol = text.find('\n', at);
  if (q1 == string::npos || (eol != string::npos && q1 > eol)) return wstring();
  size_t q2 = text.find('"', q1 + 1);
  if (q2 == string::npos) return wstring();
  wstring p = fromUtf8(text.substr(q1 + 1, q2 - q1 - 1));
  while (!p.empty() && (p.back() == L'\\' || p.back() == L'/')) p.pop_back();
  return p;
}

std::vector<Sim> detect(const wstring& roaming, const wstring& local) {
  struct Candidate {
    const wchar_t* name;
    bool untested;
    wstring data;
  };
  const std::vector<Candidate> candidates = {
      {L"MSFS 2024 (Steam)", false, roaming + L"\\Microsoft Flight Simulator 2024"},
      {L"MSFS 2020 (Steam)", false, roaming + L"\\Microsoft Flight Simulator"},
      {L"MSFS 2024 (Microsoft Store)", true, local + L"\\Packages\\Microsoft.Limitless_8wekyb3d8bbwe\\LocalCache"},
      {L"MSFS 2020 (Microsoft Store)", true, local + L"\\Packages\\Microsoft.FlightSimulator_8wekyb3d8bbwe\\LocalCache"},
  };
  std::vector<Sim> found;
  for (const auto& c : candidates) {
    const wstring packages = installedPackagesPath(c.data + L"\\UserCfg.opt");
    if (packages.empty()) continue;
    Sim s;
    s.name = c.name;
    s.untested = c.untested;
    s.data = c.data;
    s.community = packages + L"\\Community";
    found.push_back(s);
  }
  return found;
}

// ---------------------------------------------------------------- the companion process

// Stops a companion that runs from [packageDir], so its file can be replaced.
bool stopCompanion(const wstring& packageDir) {
  bool stopped = false;
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE) return false;
  PROCESSENTRY32W e;
  e.dwSize = sizeof e;
  for (BOOL ok = Process32FirstW(snap, &e); ok; ok = Process32NextW(snap, &e)) {
    if (!iequals(e.szExeFile, kExeName)) continue;
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE | SYNCHRONIZE, FALSE, e.th32ProcessID);
    if (!p) continue;
    wchar_t path[MAX_PATH * 2];
    DWORD n = (DWORD)(sizeof(path) / sizeof(path[0]));
    if (QueryFullProcessImageNameW(p, 0, path, &n) && startsWithI(path, packageDir)) {
      TerminateProcess(p, 0);
      WaitForSingleObject(p, 5000);
      stopped = true;
    }
    CloseHandle(p);
  }
  CloseHandle(snap);
  return stopped;
}

// ---------------------------------------------------------------- EXE.xml

// Adds (or updates) the start-up entry, or removes it. Returns an empty string on success, else why not.
wstring editExeXml(const wstring& xmlPath, const wstring& exePath, bool add, wstring& note) {
  string xml;
  const bool had = readFile(xmlPath, xml);
  if (!had) {
    if (!add) {
      note = L"EXE.xml not found; nothing to remove";
      return L"";
    }
    xml =
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n<SimBase.Document Type=\"Launch\" version=\"1,0\">\r\n"
        "  <Descr>Launch</Descr>\r\n  <Filename>EXE.xml</Filename>\r\n  <Disabled>False</Disabled>\r\n"
        "  <Launch.ManualLoad>False</Launch.ManualLoad>\r\n</SimBase.Document>\r\n";
  }
  const string nl = xml.find("\r\n") != string::npos ? "\r\n" : "\n";
  string original = xml;

  // Remove an existing entry of ours (so Install also updates a changed path).
  bool hadEntry = false;
  size_t b = xml.find(kBegin);
  if (b != string::npos) {
    size_t e = xml.find(kEnd, b);
    if (e == string::npos) return L"EXE.xml has the begin marker but not the end marker; not changed";
    e += string(kEnd).size();
    if (xml.compare(e, 2, "\r\n") == 0) e += 2;
    else if (xml.compare(e, 1, "\n") == 0) e += 1;
    size_t from = b;
    while (from > 0 && (xml[from - 1] == ' ' || xml[from - 1] == '\t')) --from;
    xml.erase(from, e - from);
    hadEntry = true;
  }

  if (add) {
    const size_t close = xml.rfind("</SimBase.Document>");
    if (close == string::npos) return L"EXE.xml has no </SimBase.Document>; not changed";
    string block = "  " + string(kBegin) + nl + "  <Launch.Addon>" + nl + "    <Disabled>False</Disabled>" + nl +
                   "    <ManualLoad>False</ManualLoad>" + nl + "    <Name>FlightSim Aide</Name>" + nl + "    <Path>" +
                   xmlEscape(toUtf8(exePath)) + "</Path>" + nl + "    <CommandLine>--run</CommandLine>" + nl +
                   "    <NewConsole>False</NewConsole>" + nl + "  </Launch.Addon>" + nl + "  " + kEnd + nl;
    xml.insert(close, block);
  } else if (!hadEntry) {
    note = L"no FlightSim Aide entry in EXE.xml";
    return L"";
  }

  // Keep the very first original once; later upgrades do not overwrite it.
  const wstring backup = xmlPath + L".bak-flightsimaide";
  if (had && !exists(backup)) writeFile(backup, original.data(), original.size());
  if (!writeFile(xmlPath, xml.data(), xml.size())) return L"cannot write EXE.xml (is it read-only?)";
  note = add ? (hadEntry ? L"start-up entry updated in EXE.xml" : L"start-up entry added to EXE.xml")
             : L"start-up entry removed from EXE.xml";
  if (had && add && !hadEntry) note += L" (the original is kept as EXE.xml.bak-flightsimaide)";
  return L"";
}

// ---------------------------------------------------------------- firewall

// Says whether Windows Firewall allows [exe] in on private networks. Windows asks the first time a
// program listens, but the companion starts hidden with the simulator, so the question can be missed
// behind a full screen window. An empty result means it could not be told.
wstring firewallNote(const wstring& exe) {
  const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  wstring note;
  INetFwPolicy2* policy = nullptr;
  if (SUCCEEDED(CoCreateInstance(__uuidof(NetFwPolicy2), nullptr, CLSCTX_INPROC_SERVER, __uuidof(INetFwPolicy2),
                                 (void**)&policy))) {
    VARIANT_BOOL on = VARIANT_FALSE;
    const bool privateOn = SUCCEEDED(policy->get_FirewallEnabled(NET_FW_PROFILE2_PRIVATE, &on)) && on != VARIANT_FALSE;
    if (!privateOn) {
      note = L"Windows Firewall is off for private networks: nothing to allow.";
    } else {
      bool allowed = false;
      INetFwRules* rules = nullptr;
      if (SUCCEEDED(policy->get_Rules(&rules)) && rules) {
        IUnknown* unk = nullptr;
        IEnumVARIANT* en = nullptr;
        if (SUCCEEDED(rules->get__NewEnum(&unk)) && unk && SUCCEEDED(unk->QueryInterface(IID_PPV_ARGS(&en)))) {
          VARIANT v;
          VariantInit(&v);
          ULONG got = 0;
          while (!allowed && en->Next(1, &v, &got) == S_OK && got == 1) {
            INetFwRule* rule = nullptr;
            if (v.vt == VT_DISPATCH && SUCCEEDED(v.pdispVal->QueryInterface(__uuidof(INetFwRule), (void**)&rule))) {
              BSTR app = nullptr;
              VARIANT_BOOL enabled = VARIANT_FALSE;
              NET_FW_ACTION action = NET_FW_ACTION_BLOCK;
              NET_FW_RULE_DIRECTION dir = NET_FW_RULE_DIR_OUT;
              long profiles = 0;
              rule->get_Enabled(&enabled);
              rule->get_Action(&action);
              rule->get_Direction(&dir);
              rule->get_Profiles(&profiles);
              if (SUCCEEDED(rule->get_ApplicationName(&app)) && app && enabled != VARIANT_FALSE &&
                  action == NET_FW_ACTION_ALLOW && dir == NET_FW_RULE_DIR_IN &&
                  (profiles & (NET_FW_PROFILE2_PRIVATE | NET_FW_PROFILE2_ALL)) != 0 && iequals(app, exe)) {
                allowed = true;
              }
              if (app) SysFreeString(app);
              rule->Release();
            }
            VariantClear(&v);
          }
          en->Release();
        }
        if (unk) unk->Release();
        rules->Release();
      }
      note = allowed ? L"Windows Firewall allows the program on private networks."
                     : L"Windows Firewall has no rule for the program yet. The first time the simulator starts it, "
                       L"Windows asks whether to allow it: choose Private networks, or the phone cannot connect. If "
                       L"the question never appears, allow flightsim_aide_msfs.exe in Windows Security > Firewall > "
                       L"Allow an app.";
    }
    policy->Release();
  }
  if (SUCCEEDED(init)) CoUninitialize();
  return note;
}

// ---------------------------------------------------------------- install and remove

bool loadPayload(const wchar_t* res, const void*& data, DWORD& size) {
  HRSRC r = FindResourceW(nullptr, res, RT_RCDATA);
  if (!r) return false;
  HGLOBAL g = LoadResource(nullptr, r);
  if (!g) return false;
  data = LockResource(g);
  size = SizeofResource(nullptr, r);
  return data != nullptr;
}

void addLine(wstring& report, const wstring& line) { report += L"  " + line + L"\r\n"; }

bool installTo(const Sim& s, wstring& report) {
  const wstring pkg = s.package();
  stopCompanion(pkg);
  makeDirs(pkg + L"\\companion");
  makeDirs(pkg + L"\\checklists");
  for (const Payload& p : kPayload) {
    const void* data = nullptr;
    DWORD size = 0;
    const wstring dest = pkg + L"\\" + p.path;
    if (!loadPayload(p.res, data, size)) {
      addLine(report, L"FAILED: the setup program is damaged (missing " + wstring(p.path) + L")");
      return false;
    }
    if (p.keepIfExists && exists(dest)) {
      addLine(report, L"kept your existing " + wstring(p.path));
      continue;
    }
    if (!writeFile(dest, data, size)) {
      addLine(report, L"FAILED: cannot write " + dest);
      return false;
    }
  }
  const string manifest =
      "{\r\n  \"dependencies\": [],\r\n  \"content_type\": \"MISC\",\r\n  \"title\": \"FlightSim Aide\",\r\n"
      "  \"manufacturer\": \"\",\r\n  \"creator\": \"FlightSim Aide\",\r\n  \"package_version\": \"0.2.0\",\r\n"
      "  \"minimum_game_version\": \"1.36.2\",\r\n  \"release_notes\": {\r\n    \"neutral\": {\r\n"
      "      \"LastUpdate\": \"\",\r\n      \"OlderHistory\": \"\"\r\n    }\r\n  }\r\n}\r\n";
  if (!writeFile(pkg + L"\\manifest.json", manifest.data(), manifest.size())) {
    addLine(report, L"FAILED: cannot write manifest.json");
    return false;
  }
  // layout.json lists only what the package ships and keeps unchanged: the program. The checklists
  // are yours to edit, and run.log is made at run time.
  WIN32_FILE_ATTRIBUTE_DATA fa;
  const wstring exe = s.companionExe();
  if (!GetFileAttributesExW(exe.c_str(), GetFileExInfoStandard, &fa)) {
    addLine(report, L"FAILED: the program was not written");
    return false;
  }
  ULARGE_INTEGER t;
  t.LowPart = fa.ftLastWriteTime.dwLowDateTime;
  t.HighPart = fa.ftLastWriteTime.dwHighDateTime;
  ULARGE_INTEGER sz;
  sz.LowPart = fa.nFileSizeLow;
  sz.HighPart = fa.nFileSizeHigh;
  const string layout = "{\r\n  \"content\": [\r\n    {\r\n      \"path\": \"companion/" + toUtf8(kExeName) +
                        "\",\r\n      \"size\": " + std::to_string(sz.QuadPart) + ",\r\n      \"date\": " +
                        std::to_string(t.QuadPart) + "\r\n    }\r\n  ]\r\n}\r\n";
  if (!writeFile(pkg + L"\\layout.json", layout.data(), layout.size())) {
    addLine(report, L"FAILED: cannot write layout.json");
    return false;
  }
  addLine(report, L"package written to " + pkg);
  wstring note;
  const wstring why = editExeXml(s.exeXml(), exe, true, note);
  if (!why.empty()) {
    addLine(report, L"FAILED: " + why);
    return false;
  }
  addLine(report, note);
  const wstring fwNote = firewallNote(exe);
  if (!fwNote.empty()) addLine(report, fwNote);
  return true;
}

bool removeFrom(const Sim& s, bool deleteChecklists, wstring& report) {
  const wstring pkg = s.package();
  stopCompanion(pkg);
  wstring note;
  const wstring why = editExeXml(s.exeXml(), s.companionExe(), false, note);
  if (!why.empty()) {
    addLine(report, L"FAILED: " + why);
    return false;
  }
  addLine(report, note);
  DeleteFileW((pkg + L"\\companion\\" + kExeName).c_str());
  DeleteFileW((pkg + L"\\companion\\run.log").c_str());
  RemoveDirectoryW((pkg + L"\\companion").c_str());
  DeleteFileW((pkg + L"\\manifest.json").c_str());
  DeleteFileW((pkg + L"\\layout.json").c_str());
  if (deleteChecklists) {
    for (const Payload& p : kPayload) {
      if (p.keepIfExists) DeleteFileW((pkg + L"\\" + p.path).c_str());
    }
    RemoveDirectoryW((pkg + L"\\checklists").c_str());
  }
  const bool gone = RemoveDirectoryW(pkg.c_str()) != 0;
  addLine(report, gone ? L"package folder removed" : L"your checklists folder was kept in " + pkg);
  return true;
}

// ---------------------------------------------------------------- window

std::vector<Sim> g_sims;
std::vector<HWND> g_checks;
HWND g_window = nullptr;

const int kIdInstall = 2001;
const int kIdRemove = 2002;
const int kIdClose = 2003;

std::vector<const Sim*> checked() {
  std::vector<const Sim*> out;
  for (size_t i = 0; i < g_checks.size(); ++i) {
    if (SendMessageW(g_checks[i], BM_GETCHECK, 0, 0) == BST_CHECKED) out.push_back(&g_sims[i]);
  }
  return out;
}

void act(bool install) {
  const auto chosen = checked();
  if (chosen.empty()) {
    MessageBoxW(g_window, L"Tick at least one simulator.", L"FlightSim Aide Setup", MB_OK | MB_ICONINFORMATION);
    return;
  }
  bool anyUntested = false;
  for (const Sim* s : chosen) anyUntested = anyUntested || s->untested;
  if (anyUntested &&
      MessageBox(g_window,
                 L"You ticked a Microsoft Store installation. Those locations have not been tested on a real "
                 L"installation.\r\n\r\nThe setup keeps a backup of EXE.xml, but it may not find the right folders. "
                 L"Continue?",
                 L"FlightSim Aide Setup", MB_YESNO | MB_ICONWARNING) != IDYES) {
    return;
  }
  bool deleteChecklists = false;
  if (!install) {
    deleteChecklists = MessageBox(g_window, L"Also delete your checklists folder?\r\n\r\nNo keeps it.",
                                  L"FlightSim Aide Setup", MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2) == IDYES;
  }
  wstring report;
  bool ok = true;
  for (const Sim* s : chosen) {
    report += s->name + L":\r\n";
    ok = (install ? installTo(*s, report) : removeFrom(*s, deleteChecklists, report)) && ok;
    report += L"\r\n";
  }
  if (install && ok) report += L"Start the simulator and FlightSim Aide starts with it.";
  MessageBox(g_window, report.c_str(), L"FlightSim Aide Setup", MB_OK | (ok ? MB_ICONINFORMATION : MB_ICONERROR));
}

LRESULT CALLBACK wndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
  switch (m) {
    case WM_COMMAND:
      switch (LOWORD(w)) {
        case kIdInstall: act(true); return 0;
        case kIdRemove: act(false); return 0;
        case kIdClose: DestroyWindow(h); return 0;
      }
      break;
    case WM_CLOSE:
      DestroyWindow(h);
      return 0;
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProcW(h, m, w, l);
}

HWND child(const wchar_t* cls, const wchar_t* text, DWORD style, int x, int y, int w, int h, int id) {
  HWND c = CreateWindowExW(0, cls, text, WS_CHILD | WS_VISIBLE | style, x, y, w, h, g_window, (HMENU)(INT_PTR)id,
                           GetModuleHandleW(nullptr), nullptr);
  SendMessageW(c, WM_SETFONT, (WPARAM)GetStockObject(DEFAULT_GUI_FONT), TRUE);
  return c;
}

int showWindow() {
  WNDCLASSW wc = {};
  wc.lpfnWndProc = wndProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
  wc.lpszClassName = L"FlightSimAideSetup";
  RegisterClassW(&wc);

  const int width = 700;
  int y = 14;
  const int rows = g_sims.empty() ? 1 : (int)g_sims.size();
  bool anyUntested = false;
  for (const Sim& s : g_sims) anyUntested = anyUntested || s.untested;
  const int height = 14 + 24 + rows * 26 + (anyUntested ? 56 : 8) + 46 + 50;
  RECT r = {0, 0, width, height};
  AdjustWindowRect(&r, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, FALSE);
  g_window = CreateWindowExW(0, wc.lpszClassName, L"FlightSim Aide Setup", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
                             CW_USEDEFAULT, CW_USEDEFAULT, r.right - r.left, r.bottom - r.top, nullptr, nullptr,
                             wc.hInstance, nullptr);
  if (!g_window) return 1;

  if (g_sims.empty()) {
    child(L"STATIC",
          L"No Microsoft Flight Simulator installation was found.\r\nIf it is installed somewhere unusual, run this "
          L"program from a terminal with --community <folder> --data <folder>.",
          0, 16, y, width - 32, 44, 0);
    y += 52;
  } else {
    child(L"STATIC", L"Install FlightSim Aide for these simulators:", 0, 16, y, width - 32, 20, 0);
    y += 24;
    for (size_t i = 0; i < g_sims.size(); ++i) {
      wstring label = g_sims[i].name + L"   -   " + g_sims[i].community;
      if (g_sims[i].untested) label += L"   [UNTESTED]";
      HWND c = child(L"BUTTON", label.c_str(), BS_AUTOCHECKBOX, 24, y, width - 48, 22, 1000 + (int)i);
      if (!g_sims[i].untested) SendMessageW(c, BM_SETCHECK, BST_CHECKED, 0);
      g_checks.push_back(c);
      y += 26;
    }
    if (anyUntested) {
      child(L"STATIC",
            L"[UNTESTED]: the Microsoft Store versions keep their files in other places and this setup has not been "
            L"tried on them. A backup of EXE.xml is made before it is changed.",
            0, 16, y + 4, width - 32, 44, 0);
      y += 56;
    } else {
      y += 8;
    }
  }
  if (!g_sims.empty()) {
    child(L"BUTTON", L"Install", BS_DEFPUSHBUTTON, width - 3 * 100 - 16 - 16, height - 44, 92, 28, kIdInstall);
    child(L"BUTTON", L"Remove", 0, width - 2 * 100 - 16 - 8, height - 44, 92, 28, kIdRemove);
  }
  child(L"BUTTON", L"Close", 0, width - 100 - 16, height - 44, 92, 28, kIdClose);

  // centre
  RECT wr;
  GetWindowRect(g_window, &wr);
  const int sw = GetSystemMetrics(SM_CXSCREEN), sh = GetSystemMetrics(SM_CYSCREEN);
  SetWindowPos(g_window, nullptr, (sw - (wr.right - wr.left)) / 2, (sh - (wr.bottom - wr.top)) / 3, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER);
  ShowWindow(g_window, SW_SHOW);
  UpdateWindow(g_window);

  MSG msg;
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    if (!IsDialogMessageW(g_window, &msg)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
  }
  return 0;
}

// ---------------------------------------------------------------- command line

void print(const wstring& w) {
  const string s = toUtf8(w);
  std::fwrite(s.data(), 1, s.size(), stdout);
  std::fflush(stdout);
}

int commandLine(int argc, wchar_t** argv) {
  if (AttachConsole(ATTACH_PARENT_PROCESS)) std::freopen("CONOUT$", "w", stdout);
  bool install = false, remove = false, deleteChecklists = false;
  wstring sim = L"all", community, data, root;
  for (int i = 1; i < argc; ++i) {
    const wstring a = argv[i];
    const bool more = i + 1 < argc;
    if (a == L"--install") install = true;
    else if (a == L"--remove") remove = true;
    else if (a == L"--delete-checklists") deleteChecklists = true;
    else if (a == L"--sim" && more) sim = argv[++i];
    else if (a == L"--community" && more) community = argv[++i];
    else if (a == L"--data" && more) data = argv[++i];
    else if (a == L"--root" && more) root = argv[++i];
  }
  if (install == remove) {
    print(L"Use --install or --remove.\r\n");
    return 2;
  }
  std::vector<Sim> targets;
  if (!community.empty() || !data.empty()) {
    if (community.empty() || data.empty()) {
      print(L"--community and --data go together.\r\n");
      return 2;
    }
    Sim s;
    s.name = L"explicit target";
    s.community = community;
    s.data = data;
    targets.push_back(s);
  } else {
    const wstring roaming = root.empty() ? env(L"APPDATA") : root + L"\\Roaming";
    const wstring local = root.empty() ? env(L"LOCALAPPDATA") : root + L"\\Local";
    for (const Sim& s : detect(roaming, local)) {
      const bool is2024 = s.name.find(L"2024") != wstring::npos;
      if (sim == L"all" || (sim == L"2024" && is2024) || (sim == L"2020" && !is2024)) targets.push_back(s);
    }
  }
  if (targets.empty()) {
    print(L"No simulator found.\r\n");
    return 1;
  }
  bool ok = true;
  for (const Sim& s : targets) {
    wstring report = s.name + (s.untested ? L" [UNTESTED]" : L"") + L":\r\n";
    ok = (install ? installTo(s, report) : removeFrom(s, deleteChecklists, report)) && ok;
    print(report);
  }
  return ok ? 0 : 1;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argc > 1) return commandLine(argc, argv);
  g_sims = detect(env(L"APPDATA"), env(L"LOCALAPPDATA"));
  return showWindow();
}
