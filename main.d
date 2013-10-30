module main;

import std.stdio;
import std.json;
import std.file : read;
import core.sys.windows.windows;
import std.algorithm : countUntil, filter;
import std.format : format;
import std.process;
static import std.file;
import std.uni : isLower, isUpper;
import std.range;
import std.string;
import std.array;
import std.conv;

version(Windows)
{
  extern(Windows) void OutputDebugStringA(LPCTSTR lpOutputStr);
  extern(Windows) BOOL IsDebuggerPresent();

  void InitAssertHandler()
  {
    if(IsDebuggerPresent)
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
    asm { int 3; }
  }
}

int main(string[] argv)
{
  return 0;
}

bool isCamelCase(string name)
{
  assert(name.length > 0);
  if(!name.front.isLower)
    return false;
  if(name.countUntil('_') >= 0)
    return false;
  return true;
}

unittest
{
  version(Windows) InitAssertHandler();
  assert(isCamelCase("test"));
  assert(isCamelCase("testWord"));
  assert(isCamelCase("testWordLong"));
  assert(!isCamelCase("Test"));
  assert(!isCamelCase("TEST"));
  assert(!isCamelCase("TestWord"));
  assert(!isCamelCase("test_word"));
}

bool isPascalCase(string name)
{
  if(!name.front.isUpper)
    return false;
  if(name.countUntil('_') >= 0)
    return false;
  if(name.filter!(isLower).empty)
    return false;
  return true;
}

unittest
{
  version(Windows) InitAssertHandler();
  assert(isPascalCase("Test"));
  assert(isPascalCase("PascalCase"));
  assert(!isPascalCase("TEST"));
  assert(!isPascalCase("Pascal_Case"));
  assert(!isPascalCase("test"));
}

class DStyleChecker
{
private:
  void delegate(const(char)[]) _sink;
  uint _numHistoryEntries = 0;
  JSONValue[1024] _history;
  uint _numWarnings = 0;

  enum CompositeType
  {
    struct_,
    class_,
    interface_
  }

  static struct History
  {
    private DStyleChecker _outer;
    this(DStyleChecker outer, ref JSONValue obj)
    {
      assert(obj.type == JSON_TYPE.OBJECT);
      _outer = outer;
      _outer._history[_outer._numHistoryEntries++] = obj;
      assert(_outer._numHistoryEntries < _outer._history.length);
    }

    ~this()
    {
      _outer._numHistoryEntries--;
    }
  }

  void warn(const(char)[] msg)
  {
    _numWarnings++;
    _sink(msg);
    _sink(" in ");
    for(uint i=0; i < _numHistoryEntries; i++)
    {
      if(i != 0)
        _sink(".");
      _sink(_history[i]["name"].str);
    }
    _sink("\n");
  }

  void checkValue(ref JSONValue obj)
  {
    assert(obj.type == JSON_TYPE.OBJECT);
    switch(obj["kind"].str)
    {
      case "class":
        checkComposite(obj, CompositeType.class_);
        break;
      case "struct":
        checkComposite(obj, CompositeType.struct_);
        break;
      case "interface":
        checkComposite(obj, CompositeType.interface_);
        break;
      case "module":
        checkModule(obj);
        break;
      default:
    }
  }

  void checkComposite(ref JSONValue obj, CompositeType compositeType)
  {
    auto h = History(this, obj);
    if(!isPascalCase(obj["name"].str))
    {
      warn(format("The %s '%s' is not PascalCased", to!string(compositeType)[0..$-1], obj["name"].str)); 
    }
    assert(obj["members"].type == JSON_TYPE.ARRAY);
    foreach(ref member; obj["members"].array)
    {
      assert(member["kind"].type == JSON_TYPE.STRING);
      auto protection = ("protection" in member.object) ? member["protection"].str : "public";
      auto memberName = member["name"].str;
      auto orgMemberName = memberName;
      switch(member["kind"].str)
      {
        case "variable":
          if(protection == "public")
          {
            if(memberName[0] == '_')
            {
              warn(format("The %s member '%s' may not start with a '_' because its public", to!string(compositeType)[0..$-1], memberName));
              memberName = memberName[1..$];
            }
          }
          else if(memberName[0] == '_')
            memberName = memberName[1..$];
          if(!memberName.isCamelCase)
          {
            warn(format("The %s member '%s' is not camelCased", to!string(compositeType)[0..$-1], orgMemberName));
          }
          break;
        case "function":
          if(!memberName.isCamelCase)
          {
            warn(format("The %s member function '%s' is not camelCased", to!string(compositeType)[0..$-1], orgMemberName));
          }
          break;
        default:
      }
    }
  }

  void checkModule(ref JSONValue obj)
  {
    auto h = History(this, obj);
    auto moduleNames = obj["name"].str.split(".");
    foreach(moduleName; moduleNames)
    {
      if(!moduleName.filter!(c => ((c > '9' || c < '0') && (c < 'a' || c > 'z') && c != '_')).empty)
      {
        warn(format("The module '%s' should be all lowercase and only contain the characters [a-z][0-9][_]", moduleName));
      }
    }
    assert(obj["members"].type == JSON_TYPE.ARRAY);
    foreach(ref member; obj["members"].array)
    {
      checkValue(member);
    }
  }

public:

  this(void delegate(const(char)[]) sink)
  {
    _sink = sink;
  }

  uint numWarnings() const { return _numWarnings; }

  void check(ref JSONValue root)
  {
    assert(root.type == JSON_TYPE.ARRAY);
    foreach(ref member; root.array)
    {
      checkValue(member);
    }
  }
}

unittest
{
  version(Windows) InitAssertHandler();
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
        result ~= current[0..$-1];
        write("out: ", current);
        current = "";
      }
    }

    auto checker = new DStyleChecker(&testSink);
    checker.check(root);
    assert(checker.numWarnings == result.length, "number of warnings does not match number of generated output lines");
    return result;
  }

  void compileFiles(string files, string jsonName)
  {
    if(std.file.exists("tests/" ~ jsonName))
      std.file.remove("tests/" ~ jsonName);
    auto cmd = "cd tests && dmd -c -X -Xf" ~ jsonName ~ " " ~ files;
    writeln("executing: ", cmd);
    auto result = executeShell(cmd);
    assert(result.status == 0, "generating json failed");
  } 

  void test(string name, string files, string[] expected)
  {
    compileFiles(files, name ~ ".json");
    auto result = readFileAndCheck("tests/" ~ name ~ ".json");
    foreach(e; expected)
    {
      if(result.countUntil(e) < 0)
      {
        assert(false, format("failed to find expected warning '%s' in test '%s'", e, name));
      }
    }
    if(result.length > expected.length)
    {
      foreach(r; result)
      {
        if(expected.countUntil(r) < 0)
        {
          assert(false, format("Unexpected warning '%s' in test '%s'", r, name));
        }
      }
    }
  }

  test("test0", "Badmodule.d",
  [
    "The module 'Badmodule' should be all lowercase and only contain the characters [a-z][0-9][_] in Badmodule"
  ]);

  test("test1", "test1.d",
  [
    "The class 'notGood' is not PascalCased in test1.notGood",
    "The class member '_NotGood' is not camelCased in test1.notGood",
    "The class member 'NogGood2' is not camelCased in test1.notGood",
    "The class member '_notGood3' may not start with a '_' because its public in test1.notGood",
    "The struct 'notGood2' is not PascalCased in test1.notGood2",
    "The struct member '_NotGood' is not camelCased in test1.Good2",
    "The struct member 'NogGood2' is not camelCased in test1.Good2",
    "The struct member '_notGood3' may not start with a '_' because its public in test1.Good2",
    "The class member function 'BadFunc' is not camelCased in test1.notGood"
  ]);

  test("test2", "goodsub/test2.d Badsub/test.d",
  [
    "The interface 'badInterface' is not PascalCased in goodsub.test2.badInterface",
    "The module 'Badsub' should be all lowercase and only contain the characters [a-z][0-9][_] in Badsub.test"
  ]);
}