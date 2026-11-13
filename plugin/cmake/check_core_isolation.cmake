# ctest helper: the core must stay free of XPLM and of any file access, so
# nothing in a request can ever open a file (plugin/PROTOCOL.md section 3).
#   cmake -DCORE_DIR=<plugin/src/core> -P check_core_isolation.cmake
file(GLOB files "${CORE_DIR}/*.cpp" "${CORE_DIR}/*.h")
set(bad "")
foreach(f ${files})
  file(READ "${f}" text)
  if(text MATCHES "fopen|ifstream|ofstream|std::filesystem|XPLM")
    list(APPEND bad "${f}")
  endif()
endforeach()
if(bad)
  message(FATAL_ERROR "forbidden API in core: ${bad}")
endif()
