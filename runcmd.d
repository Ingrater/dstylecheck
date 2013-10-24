module runcmd;

import core.sys.windows.windows;
import std.windows.charset;
import core.stdc.string : memset;

extern(C)
{
    struct PROCESS_INFORMATION {
        HANDLE hProcess;
        HANDLE hThread;
        DWORD dwProcessId;
        DWORD dwThreadId;
    }

    alias PROCESS_INFORMATION* LPPROCESS_INFORMATION;

    struct STARTUPINFOA {
        DWORD   cb;
        LPSTR   lpReserved;
        LPSTR   lpDesktop;
        LPSTR   lpTitle;
        DWORD   dwX;
        DWORD   dwY;
        DWORD   dwXSize;
        DWORD   dwYSize;
        DWORD   dwXCountChars;
        DWORD   dwYCountChars;
        DWORD   dwFillAttribute;
        DWORD   dwFlags;
        WORD    wShowWindow;
        WORD    cbReserved2;
        LPBYTE  lpReserved2;
        HANDLE  hStdInput;
        HANDLE  hStdOutput;
        HANDLE  hStdError;
    }

    alias STARTUPINFOA* LPSTARTUPINFOA;
    
    enum
    {
      CP_ACP                   = 0,
      CP_OEMCP                 = 1,
      CP_MACCP                 = 2,
      CP_THREAD_ACP            = 3,
      CP_SYMBOL                = 42,
      CP_UTF7                  = 65000,
      CP_UTF8                  = 65001
    }
}

extern(System)
{
    BOOL CreatePipe(
                    HANDLE* hReadPipe,
                    HANDLE* hWritePipe,
                    SECURITY_ATTRIBUTES* lpPipeAttributes,
                    DWORD nSize
                    );

    BOOL SetHandleInformation(
                              HANDLE hObject,
                              DWORD dwMask,
                              DWORD dwFlags
                              );

    BOOL
        CreateProcessA(
                       LPCSTR lpApplicationName,
                       LPSTR lpCommandLine,
                       LPSECURITY_ATTRIBUTES lpProcessAttributes,
                       LPSECURITY_ATTRIBUTES lpThreadAttributes,
                       BOOL bInheritHandles,
                       DWORD dwCreationFlags,
                       LPVOID lpEnvironment,
                       LPCSTR lpCurrentDirectory,
                       LPSTARTUPINFOA lpStartupInfo,
                       LPPROCESS_INFORMATION lpProcessInformation
                       );

    BOOL
        GetExitCodeProcess(
                           HANDLE hProcess,
                           LPDWORD lpExitCode
                           );

    BOOL
        PeekNamedPipe(
                      HANDLE hNamedPipe,
                      LPVOID lpBuffer,
                      DWORD nBufferSize,
                      LPDWORD lpBytesRead,
                      LPDWORD lpTotalBytesAvail,
                      LPDWORD lpBytesLeftThisMessage
                      );

    UINT GetKBCodePage();
}

int runcmd(string command, string inDirectory)
{
	PROCESS_INFORMATION piProcInfo; 
	STARTUPINFOA siStartInfo;
    memset( &piProcInfo, 0, PROCESS_INFORMATION.sizeof );
    memset( &siStartInfo, 0, STARTUPINFOA.sizeof );
  int cp = GetKBCodePage();
  auto szCommand = toMBSz(command, cp);
	auto szPath = toMBSz(inDirectory, cp);
  int bSuccess = CreateProcessA(null, 
                            cast(char*)szCommand,     // command line 
                            null,          // process security attributes 
                            null,          // primary thread security attributes 
                            TRUE,          // handles are inherited 
                            0,             // creation flags 
                            null,          // use parent's environment 
                            cast(char*)szPath,          // use parent's current directory 
                            &siStartInfo,  // STARTUPINFO pointer 
                            &piProcInfo);  // receives PROCESS_INFORMATION 
							  
	DWORD exitCode = -1;
  if(bSuccess)
  {
	  auto result = WaitForSingleObject(piProcInfo.hProcess, INFINITE);
	  GetExitCodeProcess(piProcInfo.hProcess, cast(LPDWORD)&exitCode);
  }
	return exitCode;
}