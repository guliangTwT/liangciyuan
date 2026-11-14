// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'popular_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$PopularController on _PopularController, Store {
  late final _$currentTagAtom =
      Atom(name: '_PopularController.currentTag', context: context);

  @override
  String get currentTag {
    _$currentTagAtom.reportRead();
    return super.currentTag;
  }

  @override
  set currentTag(String value) {
    _$currentTagAtom.reportWrite(value, super.currentTag, () {
      super.currentTag = value;
    });
  }

  late final _$currentChannelAtom =
      Atom(name: '_PopularController.currentChannel', context: context);

  @override
  HomeChannel get currentChannel {
    _$currentChannelAtom.reportRead();
    return super.currentChannel;
  }

  @override
  set currentChannel(HomeChannel value) {
    _$currentChannelAtom.reportWrite(value, super.currentChannel, () {
      super.currentChannel = value;
    });
  }

  late final _$bangumiListAtom =
      Atom(name: '_PopularController.bangumiList', context: context);

  @override
  ObservableList<BangumiItem> get bangumiList {
    _$bangumiListAtom.reportRead();
    return super.bangumiList;
  }

  @override
  set bangumiList(ObservableList<BangumiItem> value) {
    _$bangumiListAtom.reportWrite(value, super.bangumiList, () {
      super.bangumiList = value;
    });
  }

  late final _$trendListAtom =
      Atom(name: '_PopularController.trendList', context: context);

  @override
  ObservableList<BangumiItem> get trendList {
    _$trendListAtom.reportRead();
    return super.trendList;
  }

  @override
  set trendList(ObservableList<BangumiItem> value) {
    _$trendListAtom.reportWrite(value, super.trendList, () {
      super.trendList = value;
    });
  }

  late final _$shelvesAtom =
      Atom(name: '_PopularController.shelves', context: context);

  @override
  ObservableList<HomeShelf> get shelves {
    _$shelvesAtom.reportRead();
    return super.shelves;
  }

  @override
  set shelves(ObservableList<HomeShelf> value) {
    _$shelvesAtom.reportWrite(value, super.shelves, () {
      super.shelves = value;
    });
  }

  late final _$shelvesLoadedAtom =
      Atom(name: '_PopularController.shelvesLoaded', context: context);

  @override
  bool get shelvesLoaded {
    _$shelvesLoadedAtom.reportRead();
    return super.shelvesLoaded;
  }

  @override
  set shelvesLoaded(bool value) {
    _$shelvesLoadedAtom.reportWrite(value, super.shelvesLoaded, () {
      super.shelvesLoaded = value;
    });
  }

  late final _$isLoadingMoreAtom =
      Atom(name: '_PopularController.isLoadingMore', context: context);

  @override
  bool get isLoadingMore {
    _$isLoadingMoreAtom.reportRead();
    return super.isLoadingMore;
  }

  @override
  set isLoadingMore(bool value) {
    _$isLoadingMoreAtom.reportWrite(value, super.isLoadingMore, () {
      super.isLoadingMore = value;
    });
  }

  late final _$isTimeOutAtom =
      Atom(name: '_PopularController.isTimeOut', context: context);

  @override
  bool get isTimeOut {
    _$isTimeOutAtom.reportRead();
    return super.isTimeOut;
  }

  @override
  set isTimeOut(bool value) {
    _$isTimeOutAtom.reportWrite(value, super.isTimeOut, () {
      super.isTimeOut = value;
    });
  }

  late final _$loadHomeShelvesAsyncAction =
      AsyncAction('_PopularController.loadHomeShelves', context: context);

  @override
  Future<void> loadHomeShelves({bool force = false}) {
    return _$loadHomeShelvesAsyncAction
        .run(() => super.loadHomeShelves(force: force));
  }

  late final _$queryBangumiByTrendAsyncAction =
      AsyncAction('_PopularController.queryBangumiByTrend', context: context);

  @override
  Future<void> queryBangumiByTrend({String type = 'add'}) {
    return _$queryBangumiByTrendAsyncAction
        .run(() => super.queryBangumiByTrend(type: type));
  }

  late final _$queryBangumiByTagAsyncAction =
      AsyncAction('_PopularController.queryBangumiByTag', context: context);

  @override
  Future<void> queryBangumiByTag({String type = 'add'}) {
    return _$queryBangumiByTagAsyncAction
        .run(() => super.queryBangumiByTag(type: type));
  }

  @override
  String toString() {
    return '''
currentTag: ${currentTag},
currentChannel: ${currentChannel},
bangumiList: ${bangumiList},
trendList: ${trendList},
shelves: ${shelves},
shelvesLoaded: ${shelvesLoaded},
isLoadingMore: ${isLoadingMore},
isTimeOut: ${isTimeOut}
    ''';
  }
}
