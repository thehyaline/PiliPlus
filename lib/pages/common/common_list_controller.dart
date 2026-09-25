import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:get/get.dart';

abstract class CommonListController<R, T> extends CommonController<R, T> {
  int page = 1;
  bool isEnd = false;
  bool? hasFooter;

  @override
  Rx<LoadingState<List<T>?>> loadingState =
      LoadingState<List<T>?>.loading().obs;

  void handleListResponse(List<T> dataList) {}

  /// 分页加载时用于判重的唯一标识，返回 null 表示该项不参与判重
  Object? getItemKey(T item) => null;

  List<T>? getDataList(R response) {
    return response as List<T>?;
  }

  void checkIsEnd(int length) {}

  @override
  Future<void> queryData([bool isRefresh = true]) async {
    if (isLoading || (!isRefresh && isEnd)) return;
    isLoading = true;
    final LoadingState<R> res = await customGetData();
    if (res case Success(:final response)) {
      if (!customHandleResponse(isRefresh, res)) {
        final dataList = getDataList(response);
        if (dataList == null || dataList.isEmpty) {
          isEnd = true;
          if (isRefresh) {
            loadingState.value = Success(dataList);
          } else if (hasFooter == true) {
            loadingState.refresh();
          }
          isLoading = false;
          return;
        }
        handleListResponse(dataList);
        if (isRefresh) {
          checkIsEnd(dataList.length);
          loadingState.value = Success(_distinct(dataList));
        } else if (loadingState.value case Success(:final response)) {
          response!.addAll(_distinct(dataList, response));
          checkIsEnd(response.length);
          loadingState.refresh();
        }
      }
      page++;
    } else {
      if (isRefresh && !handleError(res is Error ? res.errMsg : null)) {
        loadingState.value = res as Error;
      }
    }
    isLoading = false;
  }

  /// 返回 [dataList] 中判重标识不与 [existing] 及自身重复的项，
  /// 没有可判重的项或没有重复项时直接返回原列表，避免多余的列表分配
  List<T> _distinct(List<T> dataList, [List<T>? existing]) {
    Set<Object>? keys;
    List<T>? distinct;
    for (int i = 0; i < dataList.length; i++) {
      final item = dataList[i];
      final key = getItemKey(item);
      if (key != null && !(keys ??= _collectKeys(existing)).add(key)) {
        distinct ??= dataList.sublist(0, i);
        continue;
      }
      distinct?.add(item);
    }
    return distinct ?? dataList;
  }

  Set<Object> _collectKeys(List<T>? list) {
    final keys = <Object>{};
    if (list != null) {
      for (final item in list) {
        final key = getItemKey(item);
        if (key != null) {
          keys.add(key);
        }
      }
    }
    return keys;
  }

  @override
  Future<void> onRefresh() {
    page = 1;
    isEnd = false;
    return super.onRefresh();
  }

  @override
  Future<void> onReload() {
    loadingState.value = LoadingState<List<T>?>.loading();
    return super.onReload();
  }
}
