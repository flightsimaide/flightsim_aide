#include "file_info.h"

#include <cstdio>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#else
#include <sys/stat.h>
#endif

namespace flightsim_aide {

namespace {

#ifdef _WIN32
std::wstring widen(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), &out[0], n);
  return out;
}
#endif

}  // namespace

std::optional<FileStat> statFile(const std::string& path) {
#ifdef _WIN32
  WIN32_FILE_ATTRIBUTE_DATA data;
  if (!GetFileAttributesExW(widen(path).c_str(), GetFileExInfoStandard, &data)) return std::nullopt;
  if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) return std::nullopt;
  ULARGE_INTEGER t;
  t.LowPart = data.ftLastWriteTime.dwLowDateTime;
  t.HighPart = data.ftLastWriteTime.dwHighDateTime;
  // FILETIME counts 100 ns from 1601; the Unix epoch is 11644473600 s later.
  FileStat s;
  s.modifiedMs = static_cast<int64_t>(t.QuadPart / 10000ULL) - 11644473600000LL;
  ULARGE_INTEGER size;
  size.LowPart = data.nFileSizeLow;
  size.HighPart = data.nFileSizeHigh;
  s.size = static_cast<int64_t>(size.QuadPart);
  return s;
#else
  struct stat st;
  if (::stat(path.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) return std::nullopt;
  FileStat s;
#ifdef __APPLE__
  s.modifiedMs = static_cast<int64_t>(st.st_mtimespec.tv_sec) * 1000 + st.st_mtimespec.tv_nsec / 1000000;
#else
  s.modifiedMs = static_cast<int64_t>(st.st_mtim.tv_sec) * 1000 + st.st_mtim.tv_nsec / 1000000;
#endif
  s.size = static_cast<int64_t>(st.st_size);
  return s;
#endif
}

FileRead readWholeFile(const std::string& path, int64_t maxBytes) {
  FileRead r;
  const std::optional<FileStat> before = statFile(path);
  if (!before) return r;  // missing
  r.modifiedMs = before->modifiedMs;
  r.size = before->size;
  if (before->size > maxBytes) {
    r.status = ReadStatus::tooLarge;
    return r;
  }
#ifdef _WIN32
  FILE* f = _wfopen(widen(path).c_str(), L"rb");
#else
  FILE* f = std::fopen(path.c_str(), "rb");
#endif
  if (f == nullptr) {
    r.status = ReadStatus::error;
    return r;
  }
  std::string bytes;
  char buf[16384];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) {
    bytes.append(buf, n);
    if (static_cast<int64_t>(bytes.size()) > maxBytes) break;  // grew while reading
  }
  std::fclose(f);
  if (static_cast<int64_t>(bytes.size()) > maxBytes) {
    r.status = ReadStatus::tooLarge;
    r.size = static_cast<int64_t>(bytes.size());
    return r;
  }
  // Report what was read, so size and text always agree.
  r.size = static_cast<int64_t>(bytes.size());
  r.bytes = std::move(bytes);
  r.status = ReadStatus::ok;
  return r;
}

}  // namespace flightsim_aide
