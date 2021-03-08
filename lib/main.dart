import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:log_view/scroll_handler.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  runApp(MyApp());
}

enum FilterMethod {
  allow,
  deny,
  ignore,
}

class FilterEntry {
  FilterEntry(this.pattern, this.method);
  String pattern;
  FilterMethod method;
  static FilterEntry fromJson(dynamic e) {
    var methodString = e["method"] as String;
    var method = FilterMethod.values.firstWhere((e) => e.toString().endsWith(methodString), orElse: () => FilterMethod.deny);
    return FilterEntry(e["pattern"], method);
  }

  static dynamic toJson(FilterEntry f) {
    Map<String, String> result = Map<String, String>();
    var methodString = f.method.toString();
    var idx = methodString.indexOf('.');
    if (idx >= 0) methodString = methodString.substring(idx);
    result["method"] = methodString;
    result["pattern"] = f.pattern;
    return result;
  }
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Log Viewer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Log Viewer'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class FindIntent extends Intent {}

class FindNextIntent extends Intent {}

class _MyHomePageState extends State<MyHomePage> {
  var items = [""];
  var scrollHandler;

  var search = "Scan Job";
  var directory = "c:/temp/logs/";
  var files = [
    "EndpointProtectionService.3.log",
    "EndpointProtectionService.2.log",
    "EndpointProtectionService.1.log",
    "EndpointProtectionService.log"
  ];
  var currentSearchIdx = 100;
  Map<LogicalKeySet, Intent> shortcuts;
  Map<Type, Action<Intent>> actions;
  var searchFocusNode = FocusNode();
  var listFocusNode = FocusNode();
  var filters = [
    FilterEntry("[FilterDriver]", FilterMethod.deny),
    FilterEntry("eicar", FilterMethod.allow),
  ];

  Future<List<String>> getContent() async {
    List<String> items = [];
    for (var f in files) {
      File data = new File(directory + f);
      if (!data.existsSync()) continue;
      var lines = await readLines(data);
      var filtered = lines.where((line) {
        if (line.isEmpty) return false;
        for (var f in filters) {
          if (f.method == FilterMethod.deny && line.contains(f.pattern)) return false;
          if (f.method == FilterMethod.allow && !line.contains(f.pattern)) return false;
        }
        return true;
      });
      items.addAll(filtered);
    }
    return items;
  }

  Future<List<String>> readLines(File file) async {
    try {
      return await file.readAsLines();
    } catch (e) {}
    return await file.readAsLines(encoding: systemEncoding);
  }

  Color getColor(String line) {
    if (line.contains("[error]")) return Colors.red;
    if (line.contains("[warning]")) return Colors.deepOrange;
    if (line.contains("[info]")) return Colors.orange;
    return Colors.black;
  }

  Color getBackground(int idx) {
    var line = items[idx];
    if (search != "" && line.contains(search)) return Color.fromARGB(100, 190, 190, 0);
    if (idx == scrollHandler.currentIdx) return Color.fromARGB(255, 230, 230, 230);
    return Colors.white;
  }

  int getItemCount() => items.length;

  @override
  void initState() {
    this.scrollHandler = ScrollHandler(setState, getItemCount);
    this.findController.text = search;
    shortcuts = <LogicalKeySet, Intent>{
      LogicalKeySet(LogicalKeyboardKey.pageUp, LogicalKeyboardKey.control): ScrollPageUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyJ, LogicalKeyboardKey.control): ScrollPageUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.pageDown, LogicalKeyboardKey.control): ScrollPageDownIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyK, LogicalKeyboardKey.control): ScrollPageDownIntent(),
      LogicalKeySet(LogicalKeyboardKey.end, LogicalKeyboardKey.control): ScrollToBottomIntent(),
      LogicalKeySet(LogicalKeyboardKey.home, LogicalKeyboardKey.control): ScrollToTopIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowUp): ScrollLineUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowDown): ScrollLineDownIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyF, LogicalKeyboardKey.control): FindIntent(),
      LogicalKeySet(LogicalKeyboardKey.f3, LogicalKeyboardKey.control): FindNextIntent(),
    };
    actions = <Type, Action<Intent>>{
      FindIntent: CallbackAction(onInvoke: (Intent intent) {
        editSearchString();
        return null;
      }),
      FindNextIntent: CallbackAction(onInvoke: (Intent intent) {
        findNext();
        return null;
      }),
    };
    actions.addAll(scrollHandler.actions);

    var settingsFile = File(directory + "log_view.config");
    settingsFile.readAsString().then((value) => loadFilter(value)).whenComplete(() {
      getContent().then((value) {
        this.setState(() {
          items = value;
        });
      });
    });
    super.initState();
  }

  var findController = TextEditingController();
  var editSearch = false;

  void editSearchString() {
    setState(() {
      findController.text = search;
      editSearch = true;
      searchFocusNode.requestFocus();
    });
  }

  bool handleMatch(int idx) {
    if (items[idx].contains(search)) {
      setState(() {
        currentSearchIdx = idx;
        scrollHandler.ensureVisible(idx);
      });
      return true;
    }
    return false;
  }

  Future loadFilter(String content) async {
    if (content == null) return;
    if (content == "") this.filters = [];
    var settings = json.decode(content);
    var jsonFilter = settings["filter"] as List<dynamic>;
    var f = jsonFilter.map((e) => FilterEntry.fromJson(e));
    this.filters = f.toList();
    if (filters.length == 1 && filters[0].pattern == "myFilteredString") filters.clear();
    var values = await getContent();
    this.setState(() {
      items = values;
    });
  }

  void findNext() {
    for (int idx = currentSearchIdx + 1; idx < items.length; idx++) {
      if (handleMatch(idx)) return;
    }
    setState(() {
      currentSearchIdx = -1;
    });
  }

  void findPrevious() {
    for (int idx = currentSearchIdx - 1; idx >= 0; idx--) {
      if (handleMatch(idx)) return;
    }
    setState(() {
      currentSearchIdx = -1;
    });
  }

  Future<String> editSettingsFile(String filePath, String title, {String initial}) async {
    var settingFile = File(filePath);
    String content = "";
    if (settingFile.existsSync()) {
      content = await settingFile.readAsString();
    }
    if (content == "") content = initial == null ? "" : initial;
    var txtController = TextEditingController(text: content);
    var result = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return SimpleDialog(
            title: Text(title),
            children: <Widget>[
              Container(
                  width: 600,
                  child: TextField(
                    style: GoogleFonts.sourceCodePro(),
                    minLines: 10,
                    maxLines: 50,
                    controller: txtController,
                    onSubmitted: (s) => content = s,
                  )),
              SimpleDialogOption(
                onPressed: () {
                  content = txtController.text;
                  Navigator.pop(context, true);
                },
                child: const Text('OK'),
              ),
              SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, false);
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        });
    if (result == null) result = false;
    if (!result) return null;
    settingFile.writeAsString(content);
    return content;
  }

  void reloadFilter(FilterEntry f, FilterMethod method) async {
    await await Future.delayed(Duration(milliseconds: 400));
    if (f.method == method) {
      var filterArray = filters.map((e) => FilterEntry.toJson(e));
      var filterList = List<dynamic>.empty(growable: true);
      for (var f in filterArray) filterList.add(f);

      var settingFile = File(directory + "log_view.config");
      var jsonContent = json.decode(await settingFile.readAsString());
      jsonContent["filter"] = filterList;
      var encoder = new JsonEncoder.withIndent("  ");
      var content = encoder.convert(jsonContent);
      await settingFile.writeAsString(content);
      await loadFilter(content);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Tooltip(message: "EndpointProtectionService", child: Text(widget.title)),
        actions: <Widget>[
          for (var f in filters)
            GestureDetector(
              onTap: () {
                f.method = f.method == FilterMethod.ignore ? FilterMethod.deny : FilterMethod.ignore;
                reloadFilter(f, f.method);
              },
              onSecondaryTap: () {
                f.method = f.method == FilterMethod.ignore ? FilterMethod.allow : FilterMethod.ignore;
                reloadFilter(f, f.method);
              },
              child: Container(
                  color: f.method == FilterMethod.allow
                      ? Colors.green
                      : f.method == FilterMethod.deny
                          ? Colors.red
                          : Colors.grey[400],
                  alignment: Alignment.center,
                  margin: EdgeInsets.all(12),
                  padding: EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: Text(f.pattern, style: TextStyle())),
            ),
          GestureDetector(
              child: Icon(Icons.filter_list_alt),
              onTap: () async {
                var settingFile = directory + "log_view.config";
                var content = await editSettingsFile(settingFile, "Edit filter", initial: """
{
  "filter": [
    {"pattern":"myFilteredString", "method":"deny"}
  ]
}
""");
                await loadFilter(content);
              }),
          Container(width: 60, child: Text("")),
          editSearch
              ? Container(
                  padding: EdgeInsets.all(5),
                  width: 200,
                  height: 20,
                  color: Color.fromARGB(255, 230, 230, 230),
                  child: TextField(
                    controller: findController,
                    focusNode: searchFocusNode,
                    onSubmitted: (s) {
                      setState(() {
                        search = s;
                        editSearch = false;
                        listFocusNode.requestFocus();
                        findNext();
                      });
                    },
                  ),
                )
              : Row(
                  children: [
                    GestureDetector(
                      child: Text(search),
                      onDoubleTap: editSearchString,
                    ),
                    GestureDetector(
                      child: Icon(
                        Icons.find_in_page,
                        size: 32,
                      ),
                      onTap: editSearchString,
                    ),
                    Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      GestureDetector(child: Icon(Icons.navigate_next), onTap: findNext),
                      GestureDetector(
                        child: Icon(Icons.navigate_before),
                        onTap: findPrevious,
                      )
                    ])
                  ],
                ),
          Container(width: 20, child: Text("")),
          GestureDetector(
            child: Icon(Icons.settings),
            onTap: () async {
              var fileName = path.join((await getApplicationDocumentsDirectory()).toString(), "log_view.config");
              var content = await editSettingsFile(fileName, "Edit settings", initial: """
{
  "directory":"c:/temp/logs/",
  "files":[
    "EndpointProtectionService.3.log", 
    "EndpointProtectionService.2.log", 
    "EndpointProtectionService.1.log",
    "EndpointProtectionService.log", 
  ]
}
""");
              if (content == "") content = "{}";
              if (content == null) return;
              var settings = jsonDecode(content);
              setState(() {
                directory = settings["directory"];
                files = (settings["files"] as List<dynamic>).cast<String>();
              });
            },
          ),
          Container(width: 60, child: Text("")),
        ],
      ),
      body: FocusableActionDetector(
        actions: actions,
        shortcuts: shortcuts,
        autofocus: true,
        enabled: true,
        focusNode: listFocusNode,
        child: ScrollablePositionedList.builder(
          initialScrollIndex: currentSearchIdx > 0 ? currentSearchIdx - 1 : 0,
          padding: const EdgeInsets.all(20.0),
          itemScrollController: scrollHandler.itemScrollController,
          itemPositionsListener: scrollHandler.itemPositionsListener,
          itemCount: items.length,
          itemBuilder: (context, idx) {
            if (currentSearchIdx == idx) {
              return Container(
                height: 23,
                color: Colors.yellow,
                child: SelectableText(
                  '${items[idx]}',
                  style: TextStyle(color: getColor(items[idx])),
                ),
              );
            } else {
              return GestureDetector(
                onDoubleTap: () {
                  setState(() {
                    scrollHandler.currentIdx = idx;
                  });
                },
                child: Container(
                  height: 24,
                  color: getBackground(idx),
                  child: SelectableText(
                    '${items[idx]}',
                    style: TextStyle(color: getColor(items[idx])),
                  ),
                ),
              );
            }
          },
        ),
      ),
      persistentFooterButtons: [Text("${scrollHandler.currentIdx + 1}/${items.length}")],
    );
  }
}
