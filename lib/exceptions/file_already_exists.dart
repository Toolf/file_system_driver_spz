class FileAlreadyExists implements Exception {
  @override
  String toString() {
    return "File already exists";
  }
}
