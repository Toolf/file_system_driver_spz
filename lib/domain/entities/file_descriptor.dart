enum FileType {
  unused, // 0
  regular, // 1
  directory, // 2
}

extension FileTypeExtention on FileType {
  String get name {
    switch (this) {
      case FileType.directory:
        return "directory";
      case FileType.regular:
        return "regular";
      default:
        return "unknown";
    }
  }
}

class FileDescriptor {
  final int id;
  FileType type;
  int fileSize;
  int refs; // hard links
  int blockMapAddress;

  FileDescriptor({
    required this.id,
    required this.type,
    required this.refs,
    required this.fileSize,
    required this.blockMapAddress,
  });
}
