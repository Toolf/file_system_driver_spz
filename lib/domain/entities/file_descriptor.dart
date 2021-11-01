enum FileType {
  unused, // 0
  regular, // 1
  directory, // 2
  symlink, // 3
}

extension FileTypeExtention on FileType {
  String get name {
    switch (this) {
      case FileType.directory:
        return "directory";
      case FileType.regular:
        return "regular";
      case FileType.symlink:
        return "symlink";
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
