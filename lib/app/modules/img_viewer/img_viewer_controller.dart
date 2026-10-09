import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../core/app_logging.dart';
import '../../data/database/db_library.dart';
import '../../data/models/library_entity.dart';
import '../../utils/helper_file_picker.dart';

class ImgViewerController extends GetxController {
  final images = <String>[].obs;
  final albums = <Library>[].obs;
  final albumPanelVisible = false.obs;
  final albumsLoading = false.obs;
  final albumError = ''.obs;
  final selectedAlbumRoot = ''.obs;
  final selectedIndex = 0.obs;
  final title = ''.obs;
  final videoPath = ''.obs;
  final imageQuarterTurns = <String, int>{}.obs;
  final transformationController = TransformationController();
  final thumbnailScrollController = ScrollController();
  final focusNode = FocusNode();
  int _albumSelection = 0;

  @override
  void onInit() {
    super.onInit();
    _parseArguments();
  }

  @override
  void onReady() {
    super.onReady();
    focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollThumbnailToSelected(jump: true));
  }

  @override
  void onClose() {
    _albumSelection++;
    transformationController.dispose();
    thumbnailScrollController.dispose();
    focusNode.dispose();
    super.onClose();
  }

  void _parseArguments() {
    final args = Get.arguments;

    if (args is String) {
      images.assignAll([args]);
      return;
    }

    if (args is List) {
      images.assignAll(args.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList());
      return;
    }

    if (args is Map) {
      final dataImages = args['images'] ?? args['imageUrls'] ?? args['screenshots'];
      if (dataImages is List) {
        images.assignAll(dataImages.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList());
      } else if (dataImages is String) {
        images.assignAll([dataImages]);
      }

      final dataIndex = args['initialIndex'] ?? args['index'];
      if (dataIndex is int && images.isNotEmpty) {
        selectedIndex.value = dataIndex.clamp(0, images.length - 1).toInt();
      }

      title.value = args['title']?.toString() ?? '';
      videoPath.value = args['videoPath']?.toString() ?? '';
      selectedAlbumRoot.value = args['albumRoot']?.toString() ?? '';
    }
  }

  Future<void> toggleAlbumPanel() async {
    albumPanelVisible.toggle();
    focusNode.requestFocus();
    if (albumPanelVisible.value) await loadAlbums();
  }

  Future<void> loadAlbums() async {
    if (albumsLoading.value) return;
    albumsLoading.value = true;
    albumError.value = '';
    try {
      final libraries = await DBLibrary.getAll();
      if (isClosed) return;
      albums.assignAll(libraries.where((album) => album.images?.isNotEmpty ?? false));
    } catch (e) {
      AppLog.logW('Could not load image albums: $e');
      if (!isClosed) albumError.value = 'Could not load albums. Reopen the panel to retry.';
    } finally {
      if (!isClosed) albumsLoading.value = false;
    }
  }

  Future<void> selectAlbum(Library? album) async {
    final selection = ++_albumSelection;
    bool cancelled() => isClosed || selection != _albumSelection;
    try {
      if (album != null && !await Directory(album.rootFolder ?? '').exists()) return;
      if (cancelled()) return;
      final paths = album == null ? albums.expand((item) => item.images ?? <String>[]) : album.images ?? <String>[];
      final available = await HelperFilePicker.existingImages(paths, cancelled: cancelled);
      if (cancelled()) return;
      albumError.value = '';
      selectedIndex.value = 0;
      images.assignAll(available);
      selectedAlbumRoot.value = album?.rootFolder ?? 'all';
      title.value = album == null ? 'All'.tr : album.alias?.trim().isNotEmpty == true ? album.alias! : p.basename(album.rootFolder ?? '');
      videoPath.value = '';
      resetZoom();
      focusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) _scrollThumbnailToSelected(jump: true);
      });
    } catch (e) {
      AppLog.logW('Could not select image album: $e');
      if (!cancelled()) albumError.value = 'Could not open image album. Check folder permissions and try again.'.tr;
    }
  }

  String get currentImage => images.isEmpty ? '' : images[selectedIndex.value];
  String get currentTitle {
    final current = currentImage.trim();
    if (current.isEmpty) return title.value.isEmpty ? 'Image Viewer'.tr : title.value;

    final uri = Uri.tryParse(current);
    final filename = uri != null && uri.hasScheme && uri.pathSegments.isNotEmpty ? uri.pathSegments.last : p.basename(current);
    return filename.isEmpty ? (title.value.isEmpty ? 'Image Viewer'.tr : title.value) : filename;
  }
  bool get canGoPrevious => selectedIndex.value > 0;
  bool get canGoNext => selectedIndex.value < images.length - 1;

  void previous() {
    if (!canGoPrevious) return;
    selectImage(selectedIndex.value - 1);
  }

  void next() {
    if (!canGoNext) return;
    selectImage(selectedIndex.value + 1);
  }

  void shuffleImages() {
    if (images.length <= 1) return;
    final shuffled = images.toList()..shuffle();
    images.assignAll(shuffled);

    selectedIndex.value = 0;
    resetZoom();
    _scrollThumbnailToSelected();
  }

  void selectImage(int index) {
    if (images.isEmpty) return;
    selectedIndex.value = index.clamp(0, images.length - 1).toInt();
    resetZoom();
    _scrollThumbnailToSelected();
  }

  void zoomIn() {
    _setZoom(1.2);
  }

  void zoomOut() {
    _setZoom(0.8);
  }

  void resetZoom() {
    transformationController.value = Matrix4.identity();
  }

  void rotateClockwise() {
    if (currentImage.isEmpty) return;
    final key = currentImage;
    final currentTurn = imageQuarterTurns[key] ?? 0;
    imageQuarterTurns[key] = (currentTurn + 1) % 4;
  }

  void rotateCounterClockwise() {
    if (currentImage.isEmpty) return;
    final key = currentImage;
    final currentTurn = imageQuarterTurns[key] ?? 0;
    imageQuarterTurns[key] = (currentTurn + 3) % 4;
  }

  int getCurrentQuarterTurns() {
    if (currentImage.isEmpty) return 0;
    return imageQuarterTurns[currentImage] ?? 0;
  }

  void _setZoom(double factor) {
    final currentScale = transformationController.value.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(0.6, 5.0);
    transformationController.value = Matrix4.diagonal3Values(nextScale, nextScale, nextScale);
  }

  void _scrollThumbnailToSelected({bool jump = false}) {
    if (!thumbnailScrollController.hasClients) return;

    const itemWidth = 126.0;
    final position = thumbnailScrollController.position;
    final target = (selectedIndex.value * itemWidth) - (position.viewportDimension / 2) + (itemWidth / 2);
    final offset = target.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();

    if (jump) {
      thumbnailScrollController.jumpTo(offset);
      return;
    }

    thumbnailScrollController.animateTo(
      offset,
      duration: 160.milliseconds,
      curve: Curves.easeOut,
    );
  }
}
