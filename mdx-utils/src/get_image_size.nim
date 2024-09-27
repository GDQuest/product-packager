## Reads the header of PNG, JPEG, and WEBP files to extract the image width and height.
import streams, strformat, endians

type ImageDimensions* = object
  width*: int
  height*: int


proc readUint32BigEndian(fs: FileStream): uint32 =
  ## Reads a 32-bit unsigned integer in big-endian format from the file stream.
  var buffer: array[4, byte]
  if fs.readData(addr(buffer), 4) != 4:
    raise newException(IOError, "Failed to read 4 bytes")
  bigEndian32(addr result, addr buffer)


proc getPngDimensions(fs: FileStream): ImageDimensions =
  # Png files start with a signature that is composed of eight bytes, followed by chunks of data.
  # Each chunk starts with the chunk size, an int, followed by a 4-byte chunk type.
  # The first chunk is the IHDR (image header) chunk, which contains the image width and height.
  # /!\ The PNG format uses big-endian encoding for integers.

  # Skip PNG signature and chunk size.
  fs.setPosition(12)
  if fs.readStr(4) != "IHDR":
    raise newException(IOError, "Invalid PNG format")

  result = ImageDimensions(width: fs.readUint32BigEndian().int(), height: fs.readUint32BigEndian().int())

proc getJpegDimensions(fs: FileStream): ImageDimensions =
  # JPEG files are composed of segments, each starting with a marker.
  # The marker is a 2-byte value that starts with 0xFF and is followed by a byte that defines the segment type.
  # The segment type can be a Start Of Frame (SOF) marker, which contains the image dimensions.
  # The starter frame marker seems to not be necessarily at the start of the file. So we need to loop over segments until we find it.

  # SOF stands for Start Of Frame and is 2 bytes followed by file metadata.
  # SOF 0 to 3 are the most common markers for JPEG files.
  const
    SOF0 = 0xFFC0
    SOF3 = 0xFFC3

  # We skip the first 2 bytes in the file as they are the JPEG start of image marker.
  discard fs.readUint16()

  while not fs.atEnd():
    let marker = fs.readUint16()
    # If the marker is a SOF marker, we can extract the image dimensions.
    if marker >= SOF0 and marker <= SOF3:
      # Skip file length and precision metadata, respectively 2 and 1 bytes.
      discard fs.readUint16()
      discard fs.readUint8()
      # The next 4 bytes are the image height and width!
      result =
        ImageDimensions(height: fs.readUint16().int(), width: fs.readUint16().int())
      return

    let length = fs.readUint16().int() - 2
    if length < 0:
      raise newException(IOError, "Invalid JPEG file")
    fs.setPosition(fs.getPosition() + length - 2)

proc getWebPDimensions(fs: FileStream): ImageDimensions =
  # WebP files start with a header stating with the text 'RIFF', followed by the file size and the 'WEBP' signature.
  # The header is followed by chunks of data, each starting with a 4-byte chunk header.
  # There are three types of chunks that can contain the image dimensions: VP8, VP8L, and VP8X.
  # They correspond to the different encoding formats supported by WebP.
  # See https://developers.google.com/speed/webp/docs/riff_container for more information.

  # Skip 'RIFF' and file size
  discard fs.readUint32()
  discard fs.readUint32()
  if fs.readStr(4) != "WEBP":
    raise newException(IOError, "Not a valid WebP file")

  let chunkHeader = fs.readStr(4)
  case chunkHeader
  # Simple lossy WebP format
  of "VP8 ":
    # When we arrive here we've read the first 16 bytes of the file.
    # It is followed by 10 bytes of metadata, which we can discard.
    discard fs.readStr(10)

    # The width and height are stored in the next 4 bytes, as 14 bits each.
    result = ImageDimensions(
      width: (fs.readUint16() and 0x3FFF).int(),
      height: (fs.readUint16() and 0x3FFF).int(),
    )
  # Simple lossless WebP format
  of "VP8L":
    # Skip chunk size
    discard fs.readUint32()
    # The chunk size is followed by the signature 0x2F
    if fs.readUint8() != 0x2F:
      raise newException(IOError, "Invalid VP8L chunk")

    # The dimensions are the next 14 bits for the width and 14 bits for the height.
    let bits = fs.readUint32()
    # 0x3FFF is a mask to extract the width and height from the 32-bit value. It's the maximum value for 14 bits.
    # The webp format stores the width and height - 1, so we need to add 1 to get the actual dimensions.
    result = ImageDimensions(
      width: (bits and 0x3FFF).int() + 1, height: ((bits shr 14) and 0x3FFF).int() + 1
    )
  # Extended format with additional features like transparency
  of "VP8X":
    # Skip chunk size and metadata
    discard fs.readUint32()
    discard fs.readUint32()
    result = ImageDimensions(
      width:
        (
          fs.readUint8().uint32 or (fs.readUint8().uint32 shl 8) or
          (fs.readUint8().uint32 shl 16)
        ).int() + 1,
      height:
        (
          fs.readUint8().uint32 or (fs.readUint8().uint32 shl 8) or
          (fs.readUint8().uint32 shl 16)
        ).int() + 1,
    )
  else:
    raise newException(IOError, "Unsupported WebP format")

proc getImageDimensions*(filePath: string): ImageDimensions =
  var fs = newFileStream(filePath, fmRead)
  if fs == nil:
    raise newException(IOError, "Cannot open the file")
  defer:
    fs.close()

  let fileHeader = fs.readStr(4)
  fs.setPosition(0)
  case fileHeader
  of "\x89PNG":
    result = getPngDimensions(fs)
  of "\xFF\xD8\xFF\xE0":
    result = getJpegDimensions(fs)
  of "RIFF":
    result = getWebPDimensions(fs)
  else:
    raise newException(IOError, "Unknown image format")

when isMainModule:
  let imageFiles = @["test.png", "test.jpg", "test.webp"]
  for file in imageFiles:
    try:
      let dimensions = getImageDimensions(file)
      echo fmt"Found dimensions for {file}: {dimensions.width}x{dimensions.height}"
    except IOError:
      echo fmt"Error processing {file}: {getCurrentExceptionMsg()}"
