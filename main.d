module main;

import std.stdio;
import std.json;
import std.file : read;
import core.sys.windows.windows;
import runcmd;
import std.algorithm : countUntil;
import std.format : format;

extern(Windows) void OutputDebugStringA(LPCTSTR lpOutputStr);

int main(string[] argv)
{
   return 0;
}

void InitAssertHandler()
{
  core.exception.assertHandler = &AssertHandler;
  version(none) version(Win64)
  {
    auto handle = LoadLibraryA("msvcrt.dll".ptr);
    _CrtDbgReport = cast(_CrtDbgReport_t)GetProcAddress(handle, "_CrtDbgReport".ptr);
  }
}

void AssertHandler( string file, size_t line, string msg ) nothrow
{
  char[2048] buffer;
  sprintf(buffer.ptr, "Assertion file '%.*s' line %d: %.*s\n", file.length, file.ptr, line, msg.length, msg.ptr);
  OutputDebugStringA(buffer.ptr);
  int userResponse = 1;
  version(none) version(DigitalMars) version(Win64)
  {
    if(_CrtDbgReport != null)
    {
      userResponse = _CrtDbgReport(2, file.ptr, cast(int)line, null, "%.*s", msg.length, msg.ptr);
    }
  }
  version(GNU)
    asm { "int $0x3"; }
  else
    asm { int 3; }
}

class DStyleChecker
{
private:
  void delegate(const(char)[]) m_sink;
  uint m_numHistoryEntries = 0;
  JSONValue[1024] m_history;
  uint m_numWarnings = 0;

public:

  this(void delegate(const(char)[]) sink)
  {
    m_sink = sink;
  }

  uint numWarnings() const { return m_numWarnings; }

  void check(ref JSONValue root)
  {
  }
}

unittest
{
  InitAssertHandler();
  string[] readFileAndCheck(string filename)
  {
    auto contents = cast(const(char)[])read(filename);
    string[] result;
    string current;

    auto root = parseJSON(contents);

    void testSink(const(char)[] str)
    {
      current ~= str;
      if(current[$-1] == '\n')
      {
        result ~= current;
        str = "";
      }
    }

    auto checker = new DStyleChecker(&testSink);
    checker.check(root);
    assert(checker.numWarnings == result.length, "number of warnings does not match number of generated output lines");
    return result;
  }

  void compileFiles(string files, string jsonName)
  {
    assert(runcmd.runcmd("dmd -c -X -Xf" ~ jsonName ~ " " ~ files, "tests") == 0, "generating json failed");
  } 

  void test(string name, string files, string[] expected)
  {
    compileFiles("test1.d", name ~ ".json");
    auto result = readFileAndCheck("tests/" ~ name ~ ".json");
    foreach(e; expected)
    {
      if(result.countUntil(e) < 0)
      {
        assert(false, format("failed to find expected warning '%s' in test '%s'", e, name));
      }
    }
  }

  test("test1", "test1.d",
  [
    "the class 'notGood' should start with a upper case letter in test1.notGood"
  ]);


}