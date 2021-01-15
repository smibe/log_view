import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  runApp(MyApp());
}

enum FilterMethod {
  Allow,
  Deny,
}

class FilterEntry {
  FilterEntry(this.pattern, this.method);
  String pattern;
  FilterMethod method;
  static FilterEntry fromJson(dynamic e) {
    return FilterEntry(
        e["pattern"],
        (e["method"] as String) == "allow"
            ? FilterMethod.Allow
            : FilterMethod.Deny);
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

class ScrollPageUpIntent extends Intent {}

class ScrollPageDownIntent extends Intent {}

class ScrollToBottomIntent extends Intent {}

class ScrollToTopIntent extends Intent {}

class ScrollLineUpIntent extends Intent {}

class ScrollLineDownIntent extends Intent {}

class FindIntent extends Intent {}

class _MyHomePageState extends State<MyHomePage> {
  var items = [""];

  var search = "Scan Job";
  var directory = "c:/temp/logs/";
  var files = [
    "EndpointProtectionService.log",
    "EndpointProtectionService.3.log",
    "EndpointProtectionService.2.log",
    "EndpointProtectionService.1.log",
  ];
  var currentSearchIdx = 100;
  Map<LogicalKeySet, Intent> shortcuts;
  Map<Type, Action<Intent>> actions;
  var searchFocusNode = FocusNode();
  var listFocusNode = FocusNode();
  var filters = [
    FilterEntry("[FilterDriver]", FilterMethod.Deny),
    FilterEntry("eicar", FilterMethod.Allow),
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
          if (f.method == FilterMethod.Deny && line.contains(f.pattern))
            return false;
          if (f.method == FilterMethod.Allow && !line.contains(f.pattern))
            return false;
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
    if (search != "" && line.contains(search))
      return Color.fromARGB(100, 190, 190, 0);
    if (idx == currentIdx) return Color.fromARGB(255, 230, 230, 230);
    return Colors.white;
  }

  @override
  void initState() {
    this.findController.text = search;
    shortcuts = <LogicalKeySet, Intent>{
      LogicalKeySet(LogicalKeyboardKey.pageUp, LogicalKeyboardKey.control):
          ScrollPageUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyJ, LogicalKeyboardKey.control):
          ScrollPageUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.pageDown, LogicalKeyboardKey.control):
          ScrollPageDownIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyK, LogicalKeyboardKey.control):
          ScrollPageDownIntent(),
      LogicalKeySet(LogicalKeyboardKey.end, LogicalKeyboardKey.control):
          ScrollToBottomIntent(),
      LogicalKeySet(LogicalKeyboardKey.home, LogicalKeyboardKey.control):
          ScrollToTopIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowUp): ScrollLineUpIntent(),
      LogicalKeySet(LogicalKeyboardKey.arrowDown): ScrollLineDownIntent(),
      LogicalKeySet(LogicalKeyboardKey.keyF, LogicalKeyboardKey.control):
          FindIntent(),
    };
    actions = <Type, Action<Intent>>{
      ScrollPageUpIntent: CallbackAction(
        onInvoke: (Intent intent) => scrollPageUp(),
      ),
      ScrollPageDownIntent: CallbackAction(
        onInvoke: (Intent intent) => scrollPageDown(),
      ),
      ScrollToBottomIntent:
          CallbackAction(onInvoke: (Intent intent) => scrollToBottom()),
      ScrollToTopIntent:
          CallbackAction(onInvoke: (Intent intent) => scrollToTop()),
      ScrollLineUpIntent:
          CallbackAction(onInvoke: (Intent intent) => scrollLineUp()),
      ScrollLineDownIntent:
          CallbackAction(onInvoke: (Intent intent) => scrollLineDown()),
      FindIntent: CallbackAction(onInvoke: (Intent intent) {
        editSearchString();
        return null;
      }),
    };
    super.initState();
  }

  void scrollPageUp() {
    int count = itemPositionsListener.itemPositions.value.last.index -
        itemPositionsListener.itemPositions.value.first.index;

    int idx =
        itemPositionsListener.itemPositions.value.first.index - count * 3 ~/ 4;
    if (idx < 0) idx = 0;
    itemScrollController.jumpTo(index: idx);
  }

  void scrollToTop() {
    itemScrollController.jumpTo(index: 0);
  }

  void scrollToBottom() {
    itemScrollController.jumpTo(index: items.length);
  }

  void scrollPageDown() {
    int count = itemPositionsListener.itemPositions.value.last.index -
        itemPositionsListener.itemPositions.value.first.index;

    int idx =
        itemPositionsListener.itemPositions.value.first.index + count * 3 ~/ 4;
    if (idx > items.length - 1) idx = items.length - 1;
    itemScrollController.jumpTo(index: idx);
  }

  int currentIdx = 0;
  void scrollLineUp() {
    int idx = currentIdx - 1;
    if (idx < 0) idx = 0;

    if (idx < itemPositionsListener.itemPositions.value.first.index)
      itemScrollController.jumpTo(index: idx);
    setState(() {
      currentIdx = idx;
    });
  }

  void scrollLineDown() {
    int idx = currentIdx + 1;
    if (idx > items.length - 1) idx = items.length - 1;

    int diff = idx - itemPositionsListener.itemPositions.value.last.index + 1;
    if (diff > 0 &&
        itemPositionsListener.itemPositions.value.last.index < items.length) {
      itemScrollController.jumpTo(
          index: itemPositionsListener.itemPositions.value.first.index + diff);
    }
    setState(() {
      currentIdx = idx;
    });
  }

  var findController = TextEditingController();
  var editSearch = false;
  var itemScrollController = ItemScrollController();
  var itemPositionsListener = ItemPositionsListener.create();

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
        if (idx <= itemPositionsListener.itemPositions.value.first.index ||
            itemPositionsListener.itemPositions.value.last.index <= idx) {
          itemScrollController.jumpTo(
              index: currentSearchIdx <= 3 ? 0 : currentSearchIdx - 2);
        }
      });
      return true;
    }
    return false;
  }

  void loadFilter(String content) {
    if (content == null) return;
    if (content == "") this.filters = [];
    var settings = json.decode(content);
    var jsonFilter = settings["filter"] as List<dynamic>;
    var f = jsonFilter.map((e) => FilterEntry.fromJson(e));
    setState(() {
      this.filters = f.toList();
      if (filters.length == 1 && filters[0].pattern == "myFilteredString")
        filters.clear();
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

  Future<String> editSettingsFile(String filePath, String title,
      {String initial}) async {
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

  @override
  Widget build(BuildContext context) {
    getContent().then((value) {
      this.setState(() {
        items = value;
      });
      var settingsFile = File(directory + "log_view.config");
      settingsFile.readAsString().then((value) => loadFilter(value));
    });
    return Scaffold(
        appBar: AppBar(
          title: Tooltip(
              message: "EndpointProtectionService", child: Text(widget.title)),
          actions: <Widget>[
            for (var f in filters)
              Container(
                  color: f.method == FilterMethod.Allow
                      ? Colors.green
                      : Colors.red,
                  alignment: Alignment.center,
                  margin: EdgeInsets.all(12),
                  padding: EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: Text(f.pattern, style: TextStyle())),
            GestureDetector(
                child: Icon(Icons.filter_list_alt),
                onTap: () async {
                  var settingFile = directory + "log_view.config";
                  var content = await editSettingsFile(
                      settingFile, "Edit filter",
                      initial: """
{
  "filter": [
    {"pattern":"myFilteredString", "method":"deny"}
  ]
}
""");
                  loadFilter(content);
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
                      Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                                child: Icon(Icons.navigate_next),
                                onTap: findNext),
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
                var content = await editSettingsFile(
                    (await getApplicationDocumentsDirectory()).toString() +
                        "log_view.config",
                    "Edit settings",
                    initial: """
{
  "directory":"c:/temp/logs/",
  "files":[
    "EndpointProtectionService.log", 
    "EndpointProtectionService.3.log", 
    "EndpointProtectionService.2.log", 
    "EndpointProtectionService.1.log"
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
            itemScrollController: itemScrollController,
            itemPositionsListener: itemPositionsListener,
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
                      currentIdx = idx;
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
        ));
  }
}
