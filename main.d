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
import std.path : dirSeparator;
import std.getopt;

debug=log;

string[] keywords = [ "abstract", "alias", "align", "asm", "assert", "auto", "body", "bool", "break", "byte", "case", "cast", "catch", "cdouble", "cent", "cfloat",
                      "char", "class", "const", "continue", "creal", "dchar", "debug", "default", "delegate", "delete", "deprecated", "do", "double", "else", "enum",
                      "export", "extern", "false", "final", "finally", "float", "for", "foreach", "foreach_reverse", "function", "goto", "idouble", "if", "ifloat",
                      "immutable", "import", "in", "inout", "int", "interface", "invariant", "ireal", "is", "lazy", "long", "macro", "mixin", "module", "new",
                      "nothrow", "null", "out", "override", "package", "pragma", "private", "protected", "public", "pure", "real", "ref", "return", "scope", "shared",
                      "short", "static", "struct", "super", "switch", "synchronized", "template", "this", "throw", "true", "try", "typedef", "typeid", "typeof",
                      "ubyte", "ucent", "uint", "ulong", "union", "unittest", "ushort", "version", "void", "volatile", "wchar", "while", "with" ];
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

bool readConfig(ref DStyleChecker.Config config, const(char)[] filename)
{
  auto contents = cast(const(char)[])read(filename);
  auto root = parseJSON(contents);

  if(root.type != JSON_TYPE.OBJECT)
  {
    writefln("The root of a .json config file has to be a json object");
    return false;
  }

  if("checkForTabs" in root.object)
    if(root["checkForTabs"].type == JSON_TYPE.TRUE)
      config.checkForTabs = true;

  if("checkForCRLF" in root.object)
    if(root["checkForCRLF"].type == JSON_TYPE.TRUE)
      config.checkForCRLF = true;

  return true;
}

string helpString = q"<
Usage: dstylecheck [OPTIONS] FILE1 [FILE2 [FILE3 ...]]
Uses a .json file generated by a D compiler to do simple coding style checks.
Example: dstylecheck --root="src\\" project.json

Available options:
  --root      Root directory for the source files which have been used during compilation.
              The default is the working directory.
  --config    The .json config file to be used. 
              If this is a relative path the working directory is searched first and
              the executable directory will be searched second.
  --help      Show this help message.
>";

int main(string[] args)
{
  string configPath = "config.json";
  string rootPath = "";
  bool help = args.length <= 1;
  getopt(args,
         "--config", &configPath,
         "--root", &rootPath,
         "--help", &help);

  DStyleChecker.Config config;
  readConfig(config, configPath);
  auto checker = new DStyleChecker((str){ write(str); }, config, rootPath);

  if(help)
  {
    writeln(helpString);
  }
  
  if(args.length == 1)
  {
    writefln("no files given");
    return 1;
  }
  foreach(file; args[1..$])
  {
    if(!file.endsWith(".json"))
    {
      writefln("Don't know how to handle %s", file);
      return 1;
    }
    auto contents = cast(const(char)[])std.file.read(rootPath ~ file);
    auto json = parseJSON(contents);
    checker.check(json);
  }
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
public:
  static struct Config
  {
    bool checkForTabs;
    bool checkForCRLF;
  }

private:
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

  void delegate(const(char)[]) _sink;
  uint _numHistoryEntries = 0;
  JSONValue[1024] _history;
  uint _numWarnings = 0;
  Config _config;
  string _rootDir;
  string _currentFile;

  void warn(long lineNum, const(char)[] msg)
  {
    _numWarnings++;
    assert(_currentFile.length > 0);
    _sink(_currentFile);
    if(lineNum >= 0)
      _sink(format("(%d)", lineNum));
    _sink(": ");
    _sink(msg);
    _sink(" in ");
    foreach(size_t i, ref h; _history[0.._numHistoryEntries])
    {
      if(i != 0)
        _sink(".");
      _sink(h["name"].str);
      if(h["kind"].str == "template")
      {
        _sink("(");
        foreach(size_t j, ref param; h["parameters"].array)
        {
          if(j != 0)
            _sink(", ");
          _sink(param["name"].str);
        }
        _sink(")");
      }
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
      case "enum":
        checkEnum(obj);
        break;
      case "template":
        checkTemplate(obj);
        break;
      default:
    }
  }

  void checkComposite(ref JSONValue obj, CompositeType compositeType)
  {
    auto h = History(this, obj);
    if(!isPascalCase(obj["name"].str))
    {
      warn(("line" in obj.object) ? obj["line"].integer : -1, format("The %s '%s' is not PascalCased", to!string(compositeType)[0..$-1], obj["name"].str)); 
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
              warn(("line" in member.object) ? member["line"].integer : -1, format("The %s member '%s' may not start with a '_' because its public", to!string(compositeType)[0..$-1], memberName));
              memberName = memberName[1..$];
            }
          }
          else if(memberName[0] == '_')
            memberName = memberName[1..$];
          if(!memberName.isCamelCase)
          {
            warn(("line" in member.object) ? member["line"].integer : -1, format("The %s member '%s' is not camelCased", to!string(compositeType)[0..$-1], orgMemberName));
          }
          break;
        case "function":
          if(!memberName.isCamelCase)
          {
            warn(("line" in member.object) ? member["line"].integer : -1, format("The %s member function '%s' is not camelCased", to!string(compositeType)[0..$-1], orgMemberName));
          }
          break;
        default:
          checkValue(member);
      }
    }
  }

  void checkModule(ref JSONValue obj)
  {
    auto h = History(this, obj);
    _currentFile = obj["file"].str;

    if(_config.checkForTabs || _config.checkForCRLF)
    {
      checkFileContents(obj["file"].str);
    }

    auto moduleNames = obj["name"].str.split(".");
    foreach(moduleName; moduleNames)
    {
      if(!moduleName.filter!(c => ((c > '9' || c < '0') && (c < 'a' || c > 'z') && c != '_')).empty)
      {
        warn(("line" in obj.object) ? obj["line"].integer : -1, format("The module '%s' should be all lowercase and only contain the characters [a-z][0-9][_]", moduleName));
      }
    }
    assert(obj["members"].type == JSON_TYPE.ARRAY);
    foreach(ref member; obj["members"].array)
    {
      checkValue(member);
    }
  }

  void checkFileContents(const(char)[] filename)
  {
    auto contents = cast(const(char)[])std.file.read(_rootDir ~ filename);
    bool containsTabs = false, containsCRLF = false;
    foreach(char c; contents)
    {
      if(_config.checkForTabs && c == '\t')
      {
        containsTabs = true;
      }
      if(_config.checkForCRLF && c == '\r')
      {
        containsCRLF = true;
      }
    }
    if(containsTabs)
    {
      warn(-1, format("The file '%s' contains tabs. Spaces should be used instead", filename));
    }
    if(containsCRLF)
    {
      warn(-1, format("The file '%s' contains CRLF line endings. LF line endings should be used instead", filename));
    }
  }

  void checkEnum(ref JSONValue obj)
  {
    auto h = History(this, obj);
    auto enumName = obj["name"].str;
    if(!enumName.isPascalCase)
    {
      warn(("line" in obj.object) ? obj["line"].integer : -1, format("The enum '%s' is not PascalCased", enumName));
    }
    foreach(ref member; obj["members"].array)
    {
      auto memberName = member["name"].str;
      if(memberName[$-1] == '_')
      {
        if(keywords.countUntil(memberName[0..$-1]) < 0)
        {
          warn(("line" in member.object) ? member["line"].integer : -1, format("The enum member '%s' may not end with a '_'. Only keywords may end with a '_'", memberName));
        }
      }
      else if(!memberName.isCamelCase)
      {
        warn(("line" in member.object) ? member["line"].integer : -1, format("The enum member '%s' is not camelCased", memberName));
      }
    }
  }

  void checkTemplate(ref JSONValue obj)
  {
    auto h = History(this, obj);
    foreach(ref member; obj["members"].array)
    {
      checkValue(member);
    }
  }

public:

  this(void delegate(const(char)[]) sink, Config config, string rootDir)
  {
    _sink = sink;
    _config = config;
    _rootDir = rootDir;
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
  string[] readFileAndCheck(string filename, DStyleChecker.Config config)
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
        debug(log) write("out: ", current);
        current = "";
      }
    }

    auto checker = new DStyleChecker(&testSink, config, "tests/");
    checker.check(root);
    assert(checker.numWarnings == result.length, "number of warnings does not match number of generated output lines");
    return result;
  }

  void compileFiles(string files, string jsonName)
  {
    if(std.file.exists("tests/" ~ jsonName))
      std.file.remove("tests/" ~ jsonName);
    auto cmd = "cd tests && dmd -c -X -Xf" ~ jsonName ~ " " ~ files;
    debug(log) writeln("executing: ", cmd);
    auto result = executeShell(cmd);
    assert(result.status == 0, "generating json failed");
  } 

  void test(string name, string files, DStyleChecker.Config config, string[] expected)
  {
    compileFiles(files, name ~ ".json");
    auto result = readFileAndCheck("tests/" ~ name ~ ".json", config);
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

  DStyleChecker.Config defaultConfig;

  test("test0", "Badmodule.d", defaultConfig, 
  [
    "Badmodule.d: The module 'Badmodule' should be all lowercase and only contain the characters [a-z][0-9][_] in Badmodule"
  ]);

  string[] expected1 =
  [
    "test1.d(3): The class 'notGood' is not PascalCased in test1.notGood",
    "test1.d(7): The class member '_NotGood' is not camelCased in test1.notGood",
    "test1.d(11): The class member 'NogGood2' is not camelCased in test1.notGood",
    "test1.d(12): The class member '_notGood3' may not start with a '_' because its public in test1.notGood",
    "test1.d(14): The class member function 'BadFunc' is not camelCased in test1.notGood",
    "test1.d(22): The struct 'notGood2' is not PascalCased in test1.notGood2",
    "test1.d(30): The struct member '_NotGood' is not camelCased in test1.Good2",
    "test1.d(34): The struct member 'NogGood2' is not camelCased in test1.Good2",
    "test1.d(35): The struct member '_notGood3' may not start with a '_' because its public in test1.Good2",
    "test1.d(37): The struct member function 'BadFunc' is not camelCased in test1.Good2",
    "test1.d(43): The enum member 'BadValue' is not camelCased in test1.Good2.TestEnum",
    "test1.d(49): The enum 'badEnum' is not PascalCased in test1.Good3(T, size).Good3.badEnum",
    "test1.d(51): The enum member 'bad_Value' is not camelCased in test1.Good3(T, size).Good3.badEnum",
    "test1.d(57): The enum member 'BadValue' is not camelCased in test1.TestEnum",
    "test1.d(58): The enum member 'BADVALUE2' is not camelCased in test1.TestEnum",
    "test1.d(60): The enum member 'badValue3_' may not end with a '_'. Only keywords may end with a '_' in test1.TestEnum",
    "test1.d(61): The enum member 'badValue4__' may not end with a '_'. Only keywords may end with a '_' in test1.TestEnum",
  ];

  test("test1", "test1.d", defaultConfig, expected1);

  expected1 ~= "test1.d: The file 'test1.d' contains tabs. Spaces should be used instead in test1";
  expected1 ~= "test1.d: The file 'test1.d' contains CRLF line endings. LF line endings should be used instead in test1";

  DStyleChecker.Config extendedConfig;
  extendedConfig.checkForTabs = true;
  extendedConfig.checkForCRLF = true;
  test("test1-b", "test1.d", extendedConfig, expected1);

  test("test2", "goodsub/test2.d Badsub/test.d", defaultConfig,
  [
    "goodsub" ~ dirSeparator ~ "test2.d(3): The interface 'badInterface' is not PascalCased in goodsub.test2.badInterface",
    "Badsub" ~ dirSeparator ~ "test.d: The module 'Badsub' should be all lowercase and only contain the characters [a-z][0-9][_] in Badsub.test",
    "goodsub" ~ dirSeparator ~ "test2.d(5): The interface member function 'BadFunc' is not camelCased in goodsub.test2.badInterface"
  ]);
}