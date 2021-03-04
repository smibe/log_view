import 'package:flutter/widgets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'domo.dart';

class ScrollPageUpIntent extends Intent {}

class ScrollPageDownIntent extends Intent {}

class ScrollToBottomIntent extends Intent {}

class ScrollToTopIntent extends Intent {}

class ScrollLineUpIntent extends Intent {}

class ScrollLineDownIntent extends Intent {}

class ScrollHandler {
  ScrollHandler(this.setState, this.getItemCount) {
    actions = <Type, Action<Intent>>{
      ScrollPageUpIntent: CallbackAction(onInvoke: (Intent intent) => scrollPageUp()),
      ScrollPageDownIntent: CallbackAction(onInvoke: (Intent intent) => scrollPageDown()),
      ScrollToBottomIntent: CallbackAction(onInvoke: (Intent intent) => scrollToBottom()),
      ScrollToTopIntent: CallbackAction(onInvoke: (Intent intent) => scrollToTop()),
      ScrollLineUpIntent: CallbackAction(onInvoke: (Intent intent) => scrollLineUp()),
      ScrollLineDownIntent: CallbackAction(onInvoke: (Intent intent) => scrollLineDown()),
    };
  }

  SetState setState;
  int Function() getItemCount;
  var itemScrollController = ItemScrollController();
  var itemPositionsListener = ItemPositionsListener.create();
  int currentIdx = 0;

  Map<Type, Action<Intent>> actions;

  void scrollPageDown() {
    int count = itemPositionsListener.itemPositions.value.last.index - itemPositionsListener.itemPositions.value.first.index;

    int idx = itemPositionsListener.itemPositions.value.first.index + count * 3 ~/ 4;
    if (idx > getItemCount() - 1) idx = getItemCount() - 1;
    itemScrollController.jumpTo(index: idx);
  }

  void scrollPageUp() {
    int count = itemPositionsListener.itemPositions.value.last.index - itemPositionsListener.itemPositions.value.first.index;

    int idx = itemPositionsListener.itemPositions.value.first.index - count * 3 ~/ 4;
    if (idx < 0) idx = 0;
    itemScrollController.jumpTo(index: idx);
  }

  void scrollToTop() {
    itemScrollController.jumpTo(index: 0);
    setState(() {
      currentIdx = 0;
    });
  }

  void scrollToBottom() {
    itemScrollController.jumpTo(index: getItemCount() - 1);
    setState(() {
      currentIdx = getItemCount() - 1;
    });
  }

  void scrollLineUp() {
    int idx = currentIdx - 1;
    if (idx < 0) idx = 0;

    if (idx < itemPositionsListener.itemPositions.value.first.index) itemScrollController.jumpTo(index: idx);
    setState(() {
      currentIdx = idx;
    });
  }

  void scrollLineDown() {
    int idx = currentIdx + 1;
    if (idx > getItemCount() - 1) idx = getItemCount() - 1;

    int diff = idx - itemPositionsListener.itemPositions.value.last.index + 1;
    if (diff > 0 && itemPositionsListener.itemPositions.value.last.index < getItemCount()) {
      itemScrollController.jumpTo(index: itemPositionsListener.itemPositions.value.first.index + diff);
    }
    setState(() {
      currentIdx = idx;
    });
  }

  void ensureVisible(int idx) {
    if (idx <= itemPositionsListener.itemPositions.value.first.index || itemPositionsListener.itemPositions.value.last.index <= idx) {
      itemScrollController.jumpTo(index: idx <= 3 ? 0 : idx - 2);
    }
  }
}
