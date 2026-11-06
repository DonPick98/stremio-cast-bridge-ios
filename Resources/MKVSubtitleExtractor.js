/* mkv-subtitle-extractor: Copyright (c) 2026 Shy, MIT. Bundled notices included. */
(function(global){const modules={"src/errors.ts":function(require,exports){
/** Thrown when the server does not support HTTP Range requests */
class RangeNotSupportedError extends Error {
  constructor(url        ) {
    super(
      `The server at "${url}" does not support HTTP Range requests. ` +
      `Range requests are required for efficient subtitle extraction. ` +
      `To download the full file instead, pass { allowFullDownload: true } in options.`
    );
    this.name = 'RangeNotSupportedError';
  }
}

/** Thrown when the MKV/EBML structure is invalid or unsupported */
class MkvParseError extends Error {
  constructor(message        ) {
    super(message);
    this.name = 'MkvParseError';
  }
}


exports.RangeNotSupportedError=RangeNotSupportedError;
exports.MkvParseError=MkvParseError;
},
"src/io/range-reader.ts":function(require,exports){
const { RangeNotSupportedError }=require("src/errors.ts");

/**
 * HTTP Range-based seekable reader with read-ahead cache.
 * Falls back to full download when Range is not supported and allowFullDownload is set.
 */
class RangeReader {
          url        ;
          fileSize = 0;
          fullBuffer                    = null;
          allowFullDownload         ;
          fetchFn                         ;
          customHeaders                        ;
          _bytesDownloaded = 0;
          _requestCount = 0;

  // Read-ahead cache
          cacheOffset = -1;
          cacheBuffer                    = null;
          static          READ_AHEAD_SIZE = 32 * 1024; // 32KB

  constructor(
    url        ,
    options    
                                  
                                      
                                       
     
  ) {
    this.url = url;
    this.allowFullDownload = options?.allowFullDownload ?? false;
    this.fetchFn = options?.fetch ?? globalThis.fetch.bind(globalThis);
    this.customHeaders = options?.headers ?? {};
  }

  /** Total bytes downloaded so far */
  get bytesDownloaded()         {
    return this._bytesDownloaded;
  }

  /** Total file size in bytes */
  get size()         {
    return this.fileSize;
  }

  /** Total number of HTTP requests made */
  get requestCount()         {
    return this._requestCount;
  }

  /**
   * Initialize the reader: check Range support and get file size.
   * Pre-fetches a chunk to prime the cache for subsequent reads.
   * Must be called before read().
   */
  async init()                {
    // Fetch an initial chunk to detect Range support, get file size, and prime cache
    const probeSize = 256 * 1024; // 256KB — covers EBML header + Segment metadata
    this._requestCount++;
    const response = await this.fetchFn(this.url, {
      method: 'GET',
      headers: {
        ...this.customHeaders,
        'Range': `bytes=0-${probeSize - 1}`,
      },
    });

    if (response.status === 206) {
      // Range is supported
      const contentRange = response.headers.get('Content-Range');
      if (contentRange) {
        const match = contentRange.match(/bytes\s+\d+-\d+\/(\d+)/);
        if (match) {
          this.fileSize = parseInt(match[1], 10);
        }
      }
      const buffer = await response.arrayBuffer();
      const data = new Uint8Array(buffer);
      this._bytesDownloaded += data.length;
      // Prime cache with the initial chunk
      this.cacheOffset = 0;
      this.cacheBuffer = data;
      return;
    }

    // Range not supported
    if (!this.allowFullDownload) {
      throw new RangeNotSupportedError(this.url);
    }

    // Full download fallback
    const fullResponse = response.status === 200
      ? response
      : (this._requestCount++, await this.fetchFn(this.url, { headers: this.customHeaders }));
    const buffer = await fullResponse.arrayBuffer();
    this.fullBuffer = new Uint8Array(buffer);
    this.fileSize = this.fullBuffer.length;
    this._bytesDownloaded = this.fileSize;
  }

  /**
   * Read `length` bytes starting at `offset` from the file.
   */
  async read(offset        , length        )                      {
    if (this.fullBuffer) {
      return this.fullBuffer.slice(offset, offset + length);
    }

    // Check if request is within cache
    if (
      this.cacheBuffer &&
      this.cacheOffset >= 0 &&
      offset >= this.cacheOffset &&
      offset + length <= this.cacheOffset + this.cacheBuffer.length
    ) {
      const start = offset - this.cacheOffset;
      return this.cacheBuffer.slice(start, start + length);
    }

    // Fetch with read-ahead
    this._requestCount++;
    const readAheadLength = Math.max(length, RangeReader.READ_AHEAD_SIZE);
    const end = Math.min(offset + readAheadLength - 1, this.fileSize - 1);

    const response = await this.fetchFn(this.url, {
      headers: {
        ...this.customHeaders,
        'Range': `bytes=${offset}-${end}`,
      },
    });

    if (response.status !== 206 && response.status !== 200) {
      throw new Error(`HTTP ${response.status} fetching range ${offset}-${end}`);
    }

    const buffer = await response.arrayBuffer();
    const data = new Uint8Array(buffer);
    this._bytesDownloaded += data.length;

    // Cache the read-ahead buffer
    this.cacheOffset = offset;
    this.cacheBuffer = data;

    return data.slice(0, Math.min(length, data.length));
  }
}


exports.RangeReader=RangeReader;
},
"src/ebml/vint.ts":function(require,exports){
/** Result of reading a VINT */
                             
                          
                
                                 
                 
 

/**
 * Read a VINT-encoded element ID from a buffer at the given offset.
 * Element IDs keep all bits (including the marker bit) as part of the ID value.
 */
function readElementId(data            , offset        )             {
  if (offset >= data.length) {
    throw new Error('Unexpected end of data reading element ID');
  }

  const firstByte = data[offset];
  if (firstByte === 0) {
    throw new Error('Invalid VINT: leading byte is 0');
  }

  const width = vintWidth(firstByte);

  if (offset + width > data.length) {
    throw new Error('Unexpected end of data reading element ID');
  }

  // For element IDs, keep ALL bits (marker bit is part of the ID)
  let value = firstByte;
  for (let i = 1; i < width; i++) {
    value = (value * 256) + data[offset + i];
  }

  return { value, length: width };
}

/**
 * Read a VINT-encoded data size from a buffer at the given offset.
 * Data sizes mask out the marker bit.
 * Returns -1 for unknown size (all value bits are 1).
 */
function readDataSize(data            , offset        )             {
  if (offset >= data.length) {
    throw new Error('Unexpected end of data reading data size');
  }

  const firstByte = data[offset];
  if (firstByte === 0) {
    throw new Error('Invalid VINT: leading byte is 0');
  }

  const width = vintWidth(firstByte);

  if (offset + width > data.length) {
    throw new Error('Unexpected end of data reading data size');
  }

  // Mask out the marker bit from the first byte
  const mask = (1 << (8 - width)) - 1;
  let value = firstByte & mask;

  // Check for unknown size (all value bits are 1)
  let allOnes = (firstByte & mask) === mask;

  for (let i = 1; i < width; i++) {
    value = (value * 256) + data[offset + i];
    if (data[offset + i] !== 0xFF) {
      allOnes = false;
    }
  }

  if (allOnes) {
    return { value: -1, length: width };
  }

  return { value, length: width };
}

/**
 * Read a block track number (same encoding as data size — marker bit is masked).
 */
function readTrackNumber(data            , offset        )             {
  if (offset >= data.length) {
    throw new Error('Unexpected end of data reading track number');
  }

  const firstByte = data[offset];
  if (firstByte === 0) {
    throw new Error('Invalid VINT: leading byte is 0');
  }

  const width = vintWidth(firstByte);

  if (offset + width > data.length) {
    throw new Error('Unexpected end of data reading track number');
  }

  const mask = (1 << (8 - width)) - 1;
  let value = firstByte & mask;

  for (let i = 1; i < width; i++) {
    value = (value * 256) + data[offset + i];
  }

  return { value, length: width };
}

/** Determine the width of a VINT from its first byte */
function vintWidth(firstByte        )         {
  if (firstByte & 0x80) return 1;
  if (firstByte & 0x40) return 2;
  if (firstByte & 0x20) return 3;
  if (firstByte & 0x10) return 4;
  if (firstByte & 0x08) return 5;
  if (firstByte & 0x04) return 6;
  if (firstByte & 0x02) return 7;
  if (firstByte & 0x01) return 8;
  return 1;
}


exports.readElementId=readElementId;
exports.readDataSize=readDataSize;
exports.readTrackNumber=readTrackNumber;
},
"src/ebml/parser.ts":function(require,exports){
const { readElementId, readDataSize }=require("src/ebml/vint.ts");
                                               

/**
 * Parse an EBML element header from a buffer at the given offset.
 */
function parseElementHeader(data            , offset        )              {
  const headerOffset = offset;

  const id = readElementId(data, offset);
  offset += id.length;

  const size = readDataSize(data, offset);
  offset += size.length;

  return {
    id: id.value,
    dataSize: size.value === -1 ? -1 : size.value,
    headerOffset,
    dataOffset: offset,
    unknownSize: size.value === -1,
  };
}

/**
 * Iterate over child elements of a parent element within a buffer.
 * Yields EbmlElement for each child.
 */
function* iterateChildren(
  data            ,
  parentDataOffset        ,
  parentDataSize        ,
)                         {
  const end = parentDataOffset + parentDataSize;
  let offset = parentDataOffset;

  while (offset < end) {
    if (offset + 2 > data.length) break;

    try {
      const element = parseElementHeader(data, offset);
      yield element;

      if (element.unknownSize) break;
      offset = element.dataOffset + element.dataSize;
    } catch {
      break;
    }
  }
}

/** Read an unsigned integer from element data */
function readUint(data            , offset        , length        )         {
  let value = 0;
  for (let i = 0; i < length; i++) {
    value = value * 256 + data[offset + i];
  }
  return value;
}

/** Read a signed integer from element data */
function readSint(data            , offset        , length        )         {
  if (length === 0) return 0;
  let value = data[offset];
  if (value & 0x80) {
    value -= 256;
  }
  for (let i = 1; i < length; i++) {
    value = value * 256 + data[offset + i];
  }
  return value;
}

/** Read UTF-8 string from element data, trimming trailing null bytes */
function readUtf8(data            , offset        , length        )         {
  const decoder = new TextDecoder('utf-8');
  let end = offset + length;
  while (end > offset && data[end - 1] === 0) {
    end--;
  }
  return decoder.decode(data.subarray(offset, end));
}

/** Read a float from element data (4 or 8 bytes) */
function readFloat(data            , offset        , length        )         {
  const view = new DataView(data.buffer, data.byteOffset + offset, length);
  if (length === 4) {
    return view.getFloat32(0, false);
  } else if (length === 8) {
    return view.getFloat64(0, false);
  }
  throw new Error(`Invalid float size: ${length}`);
}

/** Read binary data from element data */
function readBinary(data            , offset        , length        )             {
  return data.slice(offset, offset + length);
}


exports.parseElementHeader=parseElementHeader;
exports.iterateChildren=iterateChildren;
exports.readUint=readUint;
exports.readSint=readSint;
exports.readUtf8=readUtf8;
exports.readFloat=readFloat;
exports.readBinary=readBinary;
},
"src/ebml/ids.ts":function(require,exports){
// EBML Header
const EBML_HEADER = 0x1A45DFA3;

// Segment
const SEGMENT = 0x18538067;

// SeekHead
const SEEK_HEAD = 0x114D9B74;
const SEEK = 0x4DBB;
const SEEK_ID = 0x53AB;
const SEEK_POSITION = 0x53AC;

// Segment Info
const INFO = 0x1549A966;
const TIMESTAMP_SCALE = 0x2AD7B1;
const DURATION = 0x4489;

// Tracks
const TRACKS = 0x1654AE6B;
const TRACK_ENTRY = 0xAE;
const TRACK_NUMBER = 0xD7;
const TRACK_TYPE = 0x83;
const CODEC_ID = 0x86;
const CODEC_PRIVATE = 0x63A2;
const LANGUAGE = 0x22B59C;
const LANGUAGE_BCP47 = 0x22B59D;
const NAME = 0x536E;
const DEFAULT_DURATION = 0x23E383;

// Attachments
const ATTACHMENTS = 0x1941A469;
const ATTACHED_FILE = 0x61A7;
const FILE_NAME = 0x466E;
const FILE_MIME_TYPE = 0x4660;
const FILE_DATA = 0x465C;

// Cluster
const CLUSTER = 0x1F43B675;
const CLUSTER_TIMESTAMP = 0xE7;
const SIMPLE_BLOCK = 0xA3;
const BLOCK_GROUP = 0xA0;
const BLOCK = 0xA1;
const BLOCK_DURATION = 0x9B;
const BLOCK_ADDITIONS = 0x75A1;
const BLOCK_MORE = 0xA6;
const BLOCK_ADD_ID = 0xEE;
const BLOCK_ADDITIONAL = 0xA5;

// Cues
const CUES = 0x1C53BB6B;
const CUE_POINT = 0xBB;
const CUE_TIME = 0xB3;
const CUE_TRACK_POSITIONS = 0xB7;
const CUE_TRACK = 0xF7;
const CUE_CLUSTER_POSITION = 0xF1;
const CUE_RELATIVE_POSITION = 0xF0;

// Chapters
const CHAPTERS = 0x1043A770;

// Tags
const TAGS = 0x1254C367;

/** Set of top-level segment children IDs (for detecting element boundaries) */
const SEGMENT_LEVEL_IDS = new Set        ([
  SEEK_HEAD, INFO, TRACKS, ATTACHMENTS, CLUSTER, CUES, CHAPTERS, TAGS,
]);


exports.EBML_HEADER=EBML_HEADER;
exports.SEGMENT=SEGMENT;
exports.SEEK_HEAD=SEEK_HEAD;
exports.SEEK=SEEK;
exports.SEEK_ID=SEEK_ID;
exports.SEEK_POSITION=SEEK_POSITION;
exports.INFO=INFO;
exports.TIMESTAMP_SCALE=TIMESTAMP_SCALE;
exports.DURATION=DURATION;
exports.TRACKS=TRACKS;
exports.TRACK_ENTRY=TRACK_ENTRY;
exports.TRACK_NUMBER=TRACK_NUMBER;
exports.TRACK_TYPE=TRACK_TYPE;
exports.CODEC_ID=CODEC_ID;
exports.CODEC_PRIVATE=CODEC_PRIVATE;
exports.LANGUAGE=LANGUAGE;
exports.LANGUAGE_BCP47=LANGUAGE_BCP47;
exports.NAME=NAME;
exports.DEFAULT_DURATION=DEFAULT_DURATION;
exports.ATTACHMENTS=ATTACHMENTS;
exports.ATTACHED_FILE=ATTACHED_FILE;
exports.FILE_NAME=FILE_NAME;
exports.FILE_MIME_TYPE=FILE_MIME_TYPE;
exports.FILE_DATA=FILE_DATA;
exports.CLUSTER=CLUSTER;
exports.CLUSTER_TIMESTAMP=CLUSTER_TIMESTAMP;
exports.SIMPLE_BLOCK=SIMPLE_BLOCK;
exports.BLOCK_GROUP=BLOCK_GROUP;
exports.BLOCK=BLOCK;
exports.BLOCK_DURATION=BLOCK_DURATION;
exports.BLOCK_ADDITIONS=BLOCK_ADDITIONS;
exports.BLOCK_MORE=BLOCK_MORE;
exports.BLOCK_ADD_ID=BLOCK_ADD_ID;
exports.BLOCK_ADDITIONAL=BLOCK_ADDITIONAL;
exports.CUES=CUES;
exports.CUE_POINT=CUE_POINT;
exports.CUE_TIME=CUE_TIME;
exports.CUE_TRACK_POSITIONS=CUE_TRACK_POSITIONS;
exports.CUE_TRACK=CUE_TRACK;
exports.CUE_CLUSTER_POSITION=CUE_CLUSTER_POSITION;
exports.CUE_RELATIVE_POSITION=CUE_RELATIVE_POSITION;
exports.CHAPTERS=CHAPTERS;
exports.TAGS=TAGS;
exports.SEGMENT_LEVEL_IDS=SEGMENT_LEVEL_IDS;
},
"src/mkv/segment.ts":function(require,exports){
const { RangeReader }=require("src/io/range-reader.ts");
const { parseElementHeader, iterateChildren, readUint }=require("src/ebml/parser.ts");
const { readElementId }=require("src/ebml/vint.ts");
const IDs=require("src/ebml/ids.ts");
const { MkvParseError }=require("src/errors.ts");
                                                                       

                                     
                                                       
                            
                                      
                          
                                                        
                           
                                      
                    
 

/**
 * Parse the EBML header and Segment element, extracting SeekHead entries and Info.
 */
async function parseSegment(reader             )                              {
  // Single read from offset 0 — covers EBML header, Segment header, and metadata area.
  // init() pre-fetches 256KB so this is typically a cache hit.
  const readSize = Math.min(256 * 1024, reader.size);
  const data = await reader.read(0, readSize);

  // Parse EBML header
  const ebmlHeader = parseElementHeader(data, 0);
  if (ebmlHeader.id !== IDs.EBML_HEADER) {
    throw new MkvParseError('Not a valid EBML file: missing EBML header');
  }

  // Parse Segment element
  const segmentStart = ebmlHeader.dataOffset + ebmlHeader.dataSize;
  const segment = parseElementHeader(data, segmentStart);
  if (segment.id !== IDs.SEGMENT) {
    throw new MkvParseError('Not a valid MKV file: missing Segment element');
  }

  const segmentDataOffset = segment.dataOffset;
  const segmentDataSize = segment.unknownSize
    ? (reader.size - segment.dataOffset)
    : segment.dataSize;

  // Metadata area starts at segmentDataOffset within the same buffer
  const metaEnd = data.length - segmentDataOffset;
  const segData = data.subarray(segmentDataOffset);

  let seekEntries              = [];
  let info              = { timestampScale: 1000000 };

  let offset = 0;
  while (offset < metaEnd - 2) {
    let element             ;
    try {
      element = parseElementHeader(segData, offset);
    } catch {
      break;
    }

    if (element.id === IDs.SEEK_HEAD) {
      const entries = parseSeekHead(segData, element);
      seekEntries.push(...entries);
    } else if (element.id === IDs.INFO) {
      info = parseInfo(segData, element);
    } else if (element.id === IDs.CLUSTER) {
      // Stop scanning at first cluster
      break;
    }

    if (element.unknownSize) break;
    offset = element.dataOffset + element.dataSize;
  }

  return { segmentDataOffset, segmentDataSize, seekEntries, info };
}

function parseSeekHead(data            , seekHeadEl             )              {
  const entries              = [];

  for (const seekEl of iterateChildren(data, seekHeadEl.dataOffset, seekHeadEl.dataSize)) {
    if (seekEl.id !== IDs.SEEK) continue;

    let seekId = 0;
    let seekPosition = 0;

    for (const child of iterateChildren(data, seekEl.dataOffset, seekEl.dataSize)) {
      if (child.id === IDs.SEEK_ID) {
        const idBytes = data.subarray(child.dataOffset, child.dataOffset + child.dataSize);
        const parsed = readElementId(idBytes, 0);
        seekId = parsed.value;
      } else if (child.id === IDs.SEEK_POSITION) {
        seekPosition = readUint(data, child.dataOffset, child.dataSize);
      }
    }

    if (seekId !== 0) {
      entries.push({ id: seekId, position: seekPosition });
    }
  }

  return entries;
}

function parseInfo(data            , infoEl             )              {
  let timestampScale = 1000000; // default: 1ms

  for (const child of iterateChildren(data, infoEl.dataOffset, infoEl.dataSize)) {
    if (child.id === IDs.TIMESTAMP_SCALE) {
      timestampScale = readUint(data, child.dataOffset, child.dataSize);
    }
  }

  return { timestampScale };
}


exports.parseSegment=parseSegment;
},
"src/mkv/tracks.ts":function(require,exports){
const { RangeReader }=require("src/io/range-reader.ts");
const { parseElementHeader, iterateChildren, readUint, readUtf8, readBinary }=require("src/ebml/parser.ts");
const IDs=require("src/ebml/ids.ts");
                                                     

const SUBTITLE_TRACK_TYPE = 17;

/**
 * Parse the Tracks element and return information about subtitle tracks.
 */
async function parseTracks(
  reader             ,
  segmentDataOffset        ,
  tracksPosition        ,
)                               {
  const absoluteOffset = segmentDataOffset + tracksPosition;

  // Read Tracks header first to get size
  const headerData = await reader.read(absoluteOffset, 12);
  const tracksEl = parseElementHeader(headerData, 0);

  // Read full Tracks element data
  const totalSize = tracksEl.dataOffset + tracksEl.dataSize;
  const tracksData = await reader.read(absoluteOffset, totalSize);

  const subtitleTracks                      = [];

  for (const entryEl of iterateChildren(tracksData, tracksEl.dataOffset, tracksEl.dataSize)) {
    if (entryEl.id !== IDs.TRACK_ENTRY) continue;

    let trackNumber = 0;
    let trackType = 0;
    let codecId = '';
    let codecPrivate                    = null;
    let language                    ;
    let trackName                    ;
    let defaultDuration                    ;

    for (const child of iterateChildren(tracksData, entryEl.dataOffset, entryEl.dataSize)) {
      switch (child.id) {
        case IDs.TRACK_NUMBER:
          trackNumber = readUint(tracksData, child.dataOffset, child.dataSize);
          break;
        case IDs.TRACK_TYPE:
          trackType = readUint(tracksData, child.dataOffset, child.dataSize);
          break;
        case IDs.CODEC_ID:
          codecId = readUtf8(tracksData, child.dataOffset, child.dataSize);
          break;
        case IDs.CODEC_PRIVATE:
          codecPrivate = readBinary(tracksData, child.dataOffset, child.dataSize);
          break;
        case IDs.LANGUAGE:
          if (language === undefined) {
            language = readUtf8(tracksData, child.dataOffset, child.dataSize);
          }
          break;
        case IDs.LANGUAGE_BCP47:
          // BCP47 takes priority over legacy Language
          language = readUtf8(tracksData, child.dataOffset, child.dataSize);
          break;
        case IDs.NAME:
          trackName = readUtf8(tracksData, child.dataOffset, child.dataSize);
          break;
        case IDs.DEFAULT_DURATION:
          defaultDuration = readUint(tracksData, child.dataOffset, child.dataSize);
          break;
      }
    }

    if (trackType === SUBTITLE_TRACK_TYPE) {
      subtitleTracks.push({
        trackNumber,
        codecId,
        codecPrivate,
        language: language === 'und' ? undefined : language,
        trackName,
        defaultDuration,
      });
    }
  }

  return subtitleTracks;
}


exports.parseTracks=parseTracks;
},
"src/mkv/cues.ts":function(require,exports){
const { RangeReader }=require("src/io/range-reader.ts");
const { parseElementHeader, iterateChildren, readUint }=require("src/ebml/parser.ts");
const IDs=require("src/ebml/ids.ts");

/** A single Cue index entry mapping a track+timestamp to a cluster position */
                           
                                                  
               
                     
                
                                                        
                          
                                                                       
                                       
 

/**
 * Parse the Cues element and return all index entries.
 */
async function parseCues(
  reader             ,
  segmentDataOffset        ,
  cuesPosition        ,
)                      {
  const absoluteOffset = segmentDataOffset + cuesPosition;

  // Read header to get total size
  const headerData = await reader.read(absoluteOffset, 12);
  const cuesEl = parseElementHeader(headerData, 0);

  // Read full Cues element data
  const totalSize = cuesEl.dataOffset + cuesEl.dataSize;
  const cuesData = await reader.read(absoluteOffset, totalSize);

  const entries             = [];

  for (const pointEl of iterateChildren(cuesData, cuesEl.dataOffset, cuesEl.dataSize)) {
    if (pointEl.id !== IDs.CUE_POINT) continue;

    let cueTime = 0;

    // First pass: get CueTime
    for (const child of iterateChildren(cuesData, pointEl.dataOffset, pointEl.dataSize)) {
      if (child.id === IDs.CUE_TIME) {
        cueTime = readUint(cuesData, child.dataOffset, child.dataSize);
        break;
      }
    }

    // Second pass: collect CueTrackPositions
    for (const child of iterateChildren(cuesData, pointEl.dataOffset, pointEl.dataSize)) {
      if (child.id !== IDs.CUE_TRACK_POSITIONS) continue;

      let track = 0;
      let clusterPosition = 0;
      let relativePosition                    ;

      for (const posChild of iterateChildren(cuesData, child.dataOffset, child.dataSize)) {
        switch (posChild.id) {
          case IDs.CUE_TRACK:
            track = readUint(cuesData, posChild.dataOffset, posChild.dataSize);
            break;
          case IDs.CUE_CLUSTER_POSITION:
            clusterPosition = readUint(cuesData, posChild.dataOffset, posChild.dataSize);
            break;
          case IDs.CUE_RELATIVE_POSITION:
            relativePosition = readUint(cuesData, posChild.dataOffset, posChild.dataSize);
            break;
        }
      }

      entries.push({ time: cueTime, track, clusterPosition, relativePosition });
    }
  }

  return entries;
}


exports.parseCues=parseCues;
},
"src/mkv/clusters.ts":function(require,exports){
const { RangeReader }=require("src/io/range-reader.ts");
const { parseElementHeader, iterateChildren, readUint }=require("src/ebml/parser.ts");
const { readTrackNumber }=require("src/ebml/vint.ts");
const IDs=require("src/ebml/ids.ts");
                                                              
                                          

const HEADER_READ_SIZE = 16; // enough for element ID (up to 4 bytes) + data size (up to 8 bytes)
const MAX_BATCH_GAP = 2 * 1024 * 1024; // 2MB — absolute cap for gap between batched blocks
const BLOCK_SIZE_ESTIMATE = 4096; // generous estimate for a subtitle block element
const READ_AHEAD = 32 * 1024; // matches RangeReader.READ_AHEAD_SIZE

                       
                 
                  
 

/**
 * Scan clusters for subtitle blocks, skipping video/audio data.
 *
 * @param reader - RangeReader instance
 * @param startOffset - Absolute file offset to start scanning (first cluster)
 * @param endOffset - Absolute file offset of end of segment
 * @param subtitleTrackNumbers - Set of track numbers that are subtitles
 * @param timestampScale - Nanoseconds per timestamp unit
 */
async function scanClusters(
  reader             ,
  startOffset        ,
  endOffset        ,
  subtitleTrackNumbers             ,
  timestampScale        ,
)                           {
  const blocks                  = [];
  let offset = startOffset;
  const tsMultiplier = timestampScale / 1_000_000; // convert raw units to milliseconds

  while (offset < endOffset) {
    const remaining = endOffset - offset;
    if (remaining < 4) break;

    const headerBuf = await reader.read(offset, Math.min(HEADER_READ_SIZE, remaining));

    let element             ;
    try {
      element = parseElementHeader(headerBuf, 0);
    } catch {
      break;
    }

    const headerSize = element.dataOffset; // bytes consumed by ID + size
    const absDataOffset = offset + headerSize;

    if (element.id === IDs.CLUSTER) {
      // Process cluster contents
      const clusterEnd = element.unknownSize
        ? endOffset
        : absDataOffset + element.dataSize;

      const { clusterBlocks, nextOffset } = await processCluster(
        reader,
        absDataOffset,
        clusterEnd,
        element.unknownSize,
        subtitleTrackNumbers,
        tsMultiplier,
      );
      blocks.push(...clusterBlocks);
      offset = nextOffset;
    } else {
      // Skip non-cluster segment-level elements
      if (element.unknownSize) break;
      offset = absDataOffset + element.dataSize;
    }
  }

  return blocks;
}

                         
                                 
                     
 

async function processCluster(
  reader             ,
  clusterDataStart        ,
  clusterEnd        ,
  unknownSize         ,
  subtitleTrackNumbers             ,
  tsMultiplier        ,
)                         {
  const blocks                  = [];
  let offset = clusterDataStart;
  let clusterTimestamp = 0;

  while (offset < clusterEnd) {
    const remaining = clusterEnd - offset;
    if (remaining < 4) break;

    const headerBuf = await reader.read(offset, Math.min(HEADER_READ_SIZE, remaining));

    let element             ;
    try {
      element = parseElementHeader(headerBuf, 0);
    } catch {
      break;
    }

    const headerSize = element.dataOffset;
    const absDataOffset = offset + headerSize;

    // For unknown-size clusters, detect next segment-level element
    if (unknownSize && IDs.SEGMENT_LEVEL_IDS.has(element.id)) {
      return { clusterBlocks: blocks, nextOffset: offset };
    }

    if (element.id === IDs.CLUSTER_TIMESTAMP) {
      // Read cluster timestamp value
      if (element.dataSize <= headerBuf.length - headerSize) {
        clusterTimestamp = readUint(headerBuf, headerSize, element.dataSize);
      } else {
        const tsData = await reader.read(absDataOffset, element.dataSize);
        clusterTimestamp = readUint(tsData, 0, element.dataSize);
      }
      offset = absDataOffset + element.dataSize;
    } else if (element.id === IDs.SIMPLE_BLOCK) {
      const block = await parseSimpleBlock(
        reader,
        absDataOffset,
        element.dataSize,
        clusterTimestamp,
        tsMultiplier,
        subtitleTrackNumbers,
      );
      if (block) blocks.push(block);
      offset = absDataOffset + element.dataSize;
    } else if (element.id === IDs.BLOCK_GROUP) {
      const groupBlocks = await processBlockGroup(
        reader,
        absDataOffset,
        element.dataSize,
        clusterTimestamp,
        tsMultiplier,
        subtitleTrackNumbers,
      );
      blocks.push(...groupBlocks);
      offset = absDataOffset + element.dataSize;
    } else {
      // Skip unknown elements
      if (element.unknownSize) break;
      offset = absDataOffset + element.dataSize;
    }
  }

  return { clusterBlocks: blocks, nextOffset: clusterEnd };
}

async function parseSimpleBlock(
  reader             ,
  dataOffset        ,
  dataSize        ,
  clusterTimestamp        ,
  tsMultiplier        ,
  subtitleTrackNumbers             ,
)                                {
  // Read enough to peek at track number (1-4 bytes VINT + 2 bytes timestamp + 1 flags)
  const peekSize = Math.min(8, dataSize);
  const peekBuf = await reader.read(dataOffset, peekSize);

  const trackVint = readTrackNumber(peekBuf, 0);
  const trackNum = trackVint.value;

  if (!subtitleTrackNumbers.has(trackNum)) {
    return null; // Skip non-subtitle block entirely
  }

  // It's a subtitle block — read the full payload
  const blockData = await reader.read(dataOffset, dataSize);

  const tsOffset = trackVint.length;
  const relativeTimestamp = (blockData[tsOffset] << 8) | blockData[tsOffset + 1];
  const signedRelTs = relativeTimestamp > 32767 ? relativeTimestamp - 65536 : relativeTimestamp;

  const payloadStart = tsOffset + 3; // track VINT + 2 ts bytes + 1 flags byte
  const payload = blockData.slice(payloadStart);

  const absoluteTimestamp = (clusterTimestamp + signedRelTs) * tsMultiplier;

  return {
    trackNumber: trackNum,
    timestampMs: absoluteTimestamp,
    durationMs: undefined,
    data: payload,
    additions: null,
  };
}

async function processBlockGroup(
  reader             ,
  groupDataStart        ,
  groupDataSize        ,
  clusterTimestamp        ,
  tsMultiplier        ,
  subtitleTrackNumbers             ,
)                           {
  // First, peek at the Block element to check the track number.
  // BlockGroup children: Block, BlockDuration, BlockAdditions, etc.
  // We need to read the group to find the Block and check its track number.
  // For efficiency, read only what we need.

  // Read the first few bytes to peek at the Block element header
  const peekSize = Math.min(32, groupDataSize);
  const peekBuf = await reader.read(groupDataStart, peekSize);

  // Quick scan: find the Block element and check its track number
  let peekOffset = 0;
  let blockTrackNum = -1;
  while (peekOffset < peekBuf.length - 4) {
    try {
      const el = parseElementHeader(peekBuf, peekOffset);
      if (el.id === IDs.BLOCK) {
        // Peek at block track number
        const blockHeaderStart = el.dataOffset;
        if (blockHeaderStart < peekBuf.length) {
          const tv = readTrackNumber(peekBuf, blockHeaderStart);
          blockTrackNum = tv.value;
        }
        break;
      }
      if (el.unknownSize) break;
      peekOffset = el.dataOffset + el.dataSize;
    } catch {
      break;
    }
  }

  if (blockTrackNum < 0 || !subtitleTrackNumbers.has(blockTrackNum)) {
    return []; // Not a subtitle block group — skip
  }

  // It's a subtitle — read the entire BlockGroup
  const groupData = await reader.read(groupDataStart, groupDataSize);

  let blockElement                     = null;
  let blockDuration                    ;
  let additions                    = null;

  for (const child of iterateChildren(groupData, 0, groupDataSize)) {
    if (child.id === IDs.BLOCK) {
      blockElement = child;
    } else if (child.id === IDs.BLOCK_DURATION) {
      blockDuration = readUint(groupData, child.dataOffset, child.dataSize);
    } else if (child.id === IDs.BLOCK_ADDITIONS) {
      additions = parseBlockAdditions(groupData, child);
    }
  }

  if (!blockElement) return [];

  const blockData = groupData.subarray(blockElement.dataOffset, blockElement.dataOffset + blockElement.dataSize);
  const trackVint = readTrackNumber(blockData, 0);

  const tsOffset = trackVint.length;
  const relativeTimestamp = (blockData[tsOffset] << 8) | blockData[tsOffset + 1];
  const signedRelTs = relativeTimestamp > 32767 ? relativeTimestamp - 65536 : relativeTimestamp;

  const payloadStart = tsOffset + 3; // track VINT + 2 ts bytes + 1 flags byte
  const payload = blockData.slice(payloadStart);

  const absoluteTimestamp = (clusterTimestamp + signedRelTs) * tsMultiplier;
  const durationMs = blockDuration !== undefined ? blockDuration * tsMultiplier : undefined;

  return [{
    trackNumber: trackVint.value,
    timestampMs: absoluteTimestamp,
    durationMs,
    data: payload,
    additions,
  }];
}

function parseBlockAdditions(data            , additionsEl             )                    {
  for (const blockMore of iterateChildren(data, additionsEl.dataOffset, additionsEl.dataSize)) {
    if (blockMore.id !== IDs.BLOCK_MORE) continue;

    for (const child of iterateChildren(data, blockMore.dataOffset, blockMore.dataSize)) {
      if (child.id === IDs.BLOCK_ADDITIONAL) {
        return data.slice(child.dataOffset, child.dataOffset + child.dataSize);
      }
    }
  }
  return null;
}

/**
 * Read subtitle blocks using Cue index entries, jumping directly to each block
 * instead of linearly scanning the entire file.
 *
 * Uses heuristic batch grouping: blocks that are close together in the file
 * (based on Cue positions) are read in a single larger HTTP request instead of
 * individual small requests. The batch threshold adapts to the file's block
 * distribution — tightly-clustered blocks (short clusters, multiple subtitle
 * tracks) trigger aggressive batching, while widely-spaced blocks use
 * conservative thresholds.
 */
async function readTargetedBlocks(
  reader             ,
  segmentDataOffset        ,
  cueEntries            ,
  subtitleTrackNumbers             ,
  timestampScale        ,
  concurrency         ,
  log                        ,
  clusterHeaderSizes                      ,
)                           {
  const blocks                  = [];
  const tsMultiplier = timestampScale / 1_000_000;
  const workers = Math.max(1, concurrency ?? 1);

  // Group entries by cluster position
  const clusterGroups = new Map                    ();
  for (const entry of cueEntries) {
    const group = clusterGroups.get(entry.clusterPosition);
    if (group) {
      group.push(entry);
    } else {
      clusterGroups.set(entry.clusterPosition, [entry]);
    }
  }

  // Probe one cluster header to learn the header size.
  // Cast Bridge supplies verified sizes per cluster: VINT widths may differ.
  const firstClusterPos = cueEntries[0].clusterPosition;
  const probeBuf = await reader.read(segmentDataOffset + firstClusterPos, HEADER_READ_SIZE);
  const clusterHeaderSize = parseElementHeader(probeBuf, 0).dataOffset;

  // Compute absolute file positions for all blocks with CueRelativePosition.
  // Blocks without it fall back to full-cluster scanning.
  const directTargets                = [];
  const fallbackClusters                         = [];

  for (const [clusterPos, entries] of clusterGroups) {
    if (entries.every(e => e.relativePosition !== undefined)) {
      for (const entry of entries) {
        directTargets.push({
          absPos: segmentDataOffset + clusterPos + (clusterHeaderSizes?.get(clusterPos) ?? clusterHeaderSize) + entry.relativePosition ,
          entry,
        });
      }
    } else {
      fallbackClusters.push([clusterPos, entries]);
    }
  }

  // Sort by file position to enable batch optimization
  directTargets.sort((a, b) => a.absPos - b.absPos);

  // ── Heuristic batch grouping ──
  // Analyze gaps between consecutive block positions. When blocks are near
  // each other (same cluster, short-duration clusters, multiple subtitle
  // tracks), a single larger read is cheaper than many individual HTTP
  // round-trips. The threshold adapts to the file's block distribution.
  if (directTargets.length > 0) {
    const batchThreshold = computeBatchThreshold(directTargets);
    const batches = groupIntoBatches(directTargets, batchThreshold);

    log?.(`[mkv-extract] Batch heuristic: ${directTargets.length} blocks → ${batches.length} read(s) (gap threshold: ${formatSize(batchThreshold)})${workers > 1 ? `, concurrency=${workers}` : ''}`);

    /** Process a single batch: one read, then parse all blocks from the buffer */
    async function processBatch(batch               )                           {
      const batchBlocks                  = [];
      const readStart = batch[0].absPos;
      const readEnd = batch[batch.length - 1].absPos + BLOCK_SIZE_ESTIMATE;
      const batchData = await reader.read(readStart, readEnd - readStart);

      for (const target of batch) {
        const localOffset = target.absPos - readStart;
        const remaining = batchData.length - localOffset;
        if (remaining < HEADER_READ_SIZE) continue;

        let elementData            ;
        let el             ;

        try {
          const headerEl = parseElementHeader(batchData, localOffset);
          const elementEnd = headerEl.dataOffset + headerEl.dataSize;

          if (elementEnd <= batchData.length) {
            // Block fits within batch buffer — zero-copy subarray
            elementData = batchData.subarray(localOffset, elementEnd);
            el = parseElementHeader(elementData, 0);
          } else {
            // Block extends beyond batch — individual read fallback
            const elementSize = headerEl.dataOffset - localOffset + headerEl.dataSize;
            elementData = await reader.read(target.absPos, elementSize);
            el = parseElementHeader(elementData, 0);
          }
        } catch {
          continue;
        }

        const block = parseBlockElement(
          elementData, el, target.entry.time * tsMultiplier,
          subtitleTrackNumbers, tsMultiplier,
        );
        if (block) batchBlocks.push(block);
      }
      return batchBlocks;
    }

    if (workers <= 1) {
      // Sequential — default, gentle on servers
      for (const batch of batches) {
        blocks.push(...await processBatch(batch));
      }
    } else {
      // Parallel with sliding-window concurrency limit
      const results = await mapConcurrent(batches, workers, processBatch);
      for (const batchBlocks of results) {
        blocks.push(...batchBlocks);
      }
    }
  }

  // Handle fallback clusters (no CueRelativePosition) — always sequential
  for (const [clusterPos] of fallbackClusters) {
    const absPos = segmentDataOffset + clusterPos;
    const headerBuf = await reader.read(absPos, HEADER_READ_SIZE);
    const clusterEl = parseElementHeader(headerBuf, 0);

    const clusterDataStart = absPos + clusterEl.dataOffset;
    const clusterEnd = clusterEl.unknownSize
      ? reader.size
      : clusterDataStart + clusterEl.dataSize;

    const { clusterBlocks } = await processCluster(
      reader, clusterDataStart, clusterEnd, clusterEl.unknownSize,
      subtitleTrackNumbers, tsMultiplier,
    );
    blocks.push(...clusterBlocks);
  }

  // Re-sort by timestamp — parallel/batched reads may produce out-of-order results
  blocks.sort((a, b) => a.timestampMs - b.timestampMs);

  return blocks;
}

/**
 * Run an async function over an array with a concurrency limit.
 * Uses a sliding-window worker pool so no worker idles while work remains.
 */
async function mapConcurrent      (
  items     ,
  concurrency        ,
  fn                         ,
)               {
  const results      = new Array(items.length);
  let nextIndex = 0;

  async function worker()                {
    while (nextIndex < items.length) {
      const i = nextIndex++;
      results[i] = await fn(items[i]);
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(concurrency, items.length) }, () => worker()),
  );
  return results;
}

/**
 * Analyze gap distribution between sorted block positions and compute an
 * adaptive batch threshold.
 *
 * - Tightly-clustered blocks (median gap < 2MB): threshold = 2× median gap,
 *   capturing most natural block groups without excessive over-read.
 * - Widely-spaced blocks: conservative 128KB threshold that only merges
 *   blocks coincidentally close (e.g., multiple blocks within one cluster).
 *
 * The threshold is always at least READ_AHEAD (32KB) since gaps smaller than
 * that are already free cache hits, and capped at MAX_BATCH_GAP (2MB).
 */
function computeBatchThreshold(targets               )         {
  if (targets.length < 2) return 0;

  const gaps           = [];
  for (let i = 1; i < targets.length; i++) {
    gaps.push(targets[i].absPos - targets[i - 1].absPos);
  }
  gaps.sort((a, b) => a - b);

  const medianGap = gaps[Math.floor(gaps.length / 2)];

  if (medianGap < MAX_BATCH_GAP) {
    // Blocks are generally clustered — use 2× median to capture most groups
    return Math.min(Math.max(medianGap * 2, READ_AHEAD), MAX_BATCH_GAP);
  }

  // Widely-spaced blocks — only merge very close ones (within-cluster pairs)
  return 128 * 1024;
}

/**
 * Group sorted block targets into batches where consecutive blocks are
 * within the given gap threshold.
 */
function groupIntoBatches(targets               , threshold        )                  {
  const batches                  = [];
  let current                = [targets[0]];

  for (let i = 1; i < targets.length; i++) {
    if (targets[i].absPos - targets[i - 1].absPos <= threshold && targets[i].absPos - current[0].absPos <= 262144) {
      current.push(targets[i]);
    } else {
      batches.push(current);
      current = [targets[i]];
    }
  }
  batches.push(current);

  return batches;
}

function formatSize(bytes        )         {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * Parse a BlockGroup or SimpleBlock element that we've jumped to directly,
 * using the CueTime as the absolute timestamp.
 */
function parseBlockElement(
  elementData            ,
  el             ,
  cueTimeMs        ,
  subtitleTrackNumbers             ,
  tsMultiplier        ,
)                       {
  if (el.id === IDs.SIMPLE_BLOCK) {
    const blockData = elementData.subarray(el.dataOffset, el.dataOffset + el.dataSize);
    const trackVint = readTrackNumber(blockData, 0);
    if (!subtitleTrackNumbers.has(trackVint.value)) return null;

    const payloadStart = trackVint.length + 3;
    return {
      trackNumber: trackVint.value,
      timestampMs: cueTimeMs,
      durationMs: undefined,
      data: blockData.slice(payloadStart),
      additions: null,
    };
  }

  if (el.id === IDs.BLOCK_GROUP) {
    let blockPayload                    = null;
    let trackNum = 0;
    let blockDuration                    ;
    let additions                    = null;

    for (const child of iterateChildren(elementData, el.dataOffset, el.dataSize)) {
      if (child.id === IDs.BLOCK) {
        const raw = elementData.subarray(child.dataOffset, child.dataOffset + child.dataSize);
        const tv = readTrackNumber(raw, 0);
        trackNum = tv.value;
        const payloadStart = tv.length + 3;
        blockPayload = raw.slice(payloadStart);
      } else if (child.id === IDs.BLOCK_DURATION) {
        blockDuration = readUint(elementData, child.dataOffset, child.dataSize);
      } else if (child.id === IDs.BLOCK_ADDITIONS) {
        additions = parseBlockAdditions(elementData, child);
      }
    }

    if (!blockPayload || !subtitleTrackNumbers.has(trackNum)) return null;

    return {
      trackNumber: trackNum,
      timestampMs: cueTimeMs,
      durationMs: blockDuration !== undefined ? blockDuration * tsMultiplier : undefined,
      data: blockPayload,
      additions,
    };
  }

  return null;
}


exports.scanClusters=scanClusters;
exports.readTargetedBlocks=readTargetedBlocks;
},
"src/util.ts":function(require,exports){
const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8');

/** Concatenate multiple Uint8Arrays into one */
function concatUint8Arrays(...arrays              )             {
  const totalLength = arrays.reduce((sum, a) => sum + a.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;
  for (const arr of arrays) {
    result.set(arr, offset);
    offset += arr.length;
  }
  return result;
}

/** Decode a Uint8Array as UTF-8 string */
function decodeUtf8(data            )         {
  return decoder.decode(data);
}

/** Encode a string as UTF-8 Uint8Array */
function encodeUtf8(text        )             {
  return encoder.encode(text);
}


exports.concatUint8Arrays=concatUint8Arrays;
exports.decodeUtf8=decodeUtf8;
exports.encodeUtf8=encodeUtf8;
},
"src/subtitle/ass.ts":function(require,exports){
const { encodeUtf8, decodeUtf8 }=require("src/util.ts");
                                                                    

/**
 * Format milliseconds as ASS timestamp: H:MM:SS.cc (centiseconds)
 */
function formatAssTimestamp(ms        )         {
  const totalCs = Math.round(ms / 10);
  const hours = Math.floor(totalCs / 360000);
  const minutes = Math.floor((totalCs % 360000) / 6000);
  const seconds = Math.floor((totalCs % 6000) / 100);
  const centis = totalCs % 100;

  return (
    String(hours) + ':' +
    String(minutes).padStart(2, '0') + ':' +
    String(seconds).padStart(2, '0') + '.' +
    String(centis).padStart(2, '0')
  );
}

/**
 * Parse an ASS block payload into its component fields.
 * Format: ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text
 * Text may contain commas, so we split on the first 8 commas only.
 */
function parseAssBlockPayload(text        )   
                    
                
                
               
                  
                  
                  
                 
                       
         {
  const parts           = [];
  let start = 0;

  // Split on first 8 commas
  for (let i = 0; i < 8; i++) {
    const commaIdx = text.indexOf(',', start);
    if (commaIdx === -1) return null;
    parts.push(text.substring(start, commaIdx));
    start = commaIdx + 1;
  }

  // Everything after the 8th comma is the Text field
  const dialogueText = text.substring(start);

  return {
    readOrder: parseInt(parts[0], 10),
    layer: parts[1],
    style: parts[2],
    name: parts[3],
    marginL: parts[4],
    marginR: parts[5],
    marginV: parts[6],
    effect: parts[7],
    dialogueText,
  };
}

/**
 * Assemble ASS/SSA subtitle file from CodecPrivate header + extracted blocks.
 */
function assembleAss(track                   , blocks                 )             {
  // CodecPrivate contains the header, which may or may not include [Events] section
  const header = track.codecPrivate ? decodeUtf8(track.codecPrivate) : '';

  // Detect line ending style from header
  const lineEnding = header.includes('\r\n') ? '\r\n' : '\n';

  // Check if CodecPrivate already includes [Events] section
  const hasEvents = header.includes('[Events]');

  // Parse and sort blocks by ReadOrder
  const parsedBlocks         
                                                                 
                         
     = [];

  for (const block of blocks) {
    const text = decodeUtf8(block.data);
    const parsed = parseAssBlockPayload(text);
    if (parsed) {
      parsedBlocks.push({ parsed, block });
    }
  }

  // Sort by ReadOrder (original muxing order)
  parsedBlocks.sort((a, b) => a.parsed.readOrder - b.parsed.readOrder);

  // Build the output
  const parts           = [];

  if (hasEvents) {
    // CodecPrivate already has [Events] and Format line
    // Trim trailing whitespace and add exactly one line ending
    parts.push(header.trimEnd() + lineEnding);
  } else {
    // Add [Events] section after header
    parts.push(header.trimEnd());
    parts.push(lineEnding + lineEnding);
    parts.push('[Events]' + lineEnding);
    parts.push('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text' + lineEnding);
  }

  for (const { parsed, block } of parsedBlocks) {
    const start = formatAssTimestamp(block.timestampMs);
    const end = formatAssTimestamp(block.timestampMs + (block.durationMs ?? 0));

    parts.push(
      `Dialogue: ${parsed.layer},${start},${end},${parsed.style},${parsed.name},` +
      `${parsed.marginL},${parsed.marginR},${parsed.marginV},${parsed.effect},${parsed.dialogueText}` +
      lineEnding
    );
  }

  // ASS files end with a trailing blank line
  parts.push(lineEnding);

  return encodeUtf8(parts.join(''));
}


exports.assembleAss=assembleAss;
},
"bridge.ts":function(require,exports){
// Cast Bridge adapter for mkv-subtitle-extractor, MIT (Shy), pinned in UPSTREAM.md.
// Only complete, frame-count-verified indexed ASS/SSA tracks are accepted.
const {RangeReader}=require("src/io/range-reader.ts");
const {parseSegment}=require("src/mkv/segment.ts");
const {parseTracks}=require("src/mkv/tracks.ts");
const {parseCues}=require("src/mkv/cues.ts");
const {readTargetedBlocks}=require("src/mkv/clusters.ts");
const {assembleAss}=require("src/subtitle/ass.ts");
const {parseElementHeader,iterateChildren,readUint,readUtf8}=require("src/ebml/parser.ts");

async function indexedASS(url       ,ordinal       ,language       ) {
  const reader=new RangeReader(url);
  await reader.init();
  const seg=await parseSegment(reader);
  const seek=(id       )=>{const e=seg.seekEntries.find(x=>x.id===id);if(!e)throw Error('index');return e.position+seg.segmentDataOffset;};
  async function element(at       ) {
    const h=parseElementHeader(await reader.read(at,12),0);
    if(h.unknownSize||h.dataSize<0||h.dataSize>524288)throw Error('limit');
    const data=await reader.read(at,h.dataOffset+h.dataSize);
    if(data.length!==h.dataOffset+h.dataSize)throw Error('truncated');
    return {data,h};
  }
  const all=await parseTracks(reader,seg.segmentDataOffset,seek(0x1654AE6B)-seg.segmentDataOffset);
  const chosen=all[ordinal];
  if(!chosen||!['S_TEXT/ASS','S_TEXT/SSA'].includes(chosen.codecId))throw Error('codec');
  const lang=(s       )=>({eng:'en',ita:'it'}[s.toLowerCase()]||s.toLowerCase());
  if(language!=='und'&&chosen.language&&lang(chosen.language)!==lang(language))throw Error('track');
  const {data:tracks,h:th}=await element(seek(0x1654AE6B));
  const hex=(data           ,o       ,n       )=>Array.from(data.subarray(o,o+n)).map(x=>x.toString(16).padStart(2,'0')).join('').replace(/^0+/,'');
  let uid='';
  for(const entry of iterateChildren(tracks,th.dataOffset,th.dataSize)) {
    if(entry.id!==0xAE)continue;
    const children=Array.from(iterateChildren(tracks,entry.dataOffset,entry.dataSize));
    const number=children.find(x=>x.id===0xD7);
    if(!number||readUint(tracks,number.dataOffset,number.dataSize)!==chosen.trackNumber)continue;
    if(children.some(x=>x.id===0x6D80))throw Error('encoding');
    const id=children.find(x=>x.id===0x73C5);if(id)uid=hex(tracks,id.dataOffset,id.dataSize);
  }
  if(!uid)throw Error('uid');
  const {data:tags,h:tagHeader}=await element(seek(0x1254C367));
  let expected=0;
  for(const tag of iterateChildren(tags,tagHeader.dataOffset,tagHeader.dataSize)) {
    if(tag.id!==0x7373)continue;
    const children=Array.from(iterateChildren(tags,tag.dataOffset,tag.dataSize));
    const targets=children.find(x=>x.id===0x63C0);if(!targets)continue;
    const ids=Array.from(iterateChildren(tags,targets.dataOffset,targets.dataSize)).filter(x=>x.id===0x63C5);
    if(!ids.some(x=>hex(tags,x.dataOffset,x.dataSize)===uid))continue;
    for(const simple of children.filter(x=>x.id===0x67C8)) {
      const fields=Array.from(iterateChildren(tags,simple.dataOffset,simple.dataSize));
      const name=fields.find(x=>x.id===0x45A3),value=fields.find(x=>x.id===0x4487);
      if(name&&value&&readUtf8(tags,name.dataOffset,name.dataSize)==='NUMBER_OF_FRAMES') {
        const v=readUtf8(tags,value.dataOffset,value.dataSize);
        if(!/^\d{1,5}$/.test(v))throw Error('count');expected=Number(v);
      }
    }
  }
  if(expected<1||expected>12000)throw Error('count');
  // Cap index size before upstream parse allocates entries.
  await element(seek(0x1C53BB6B));
  const cues=(await parseCues(reader,seg.segmentDataOffset,seek(0x1C53BB6B)-seg.segmentDataOffset)).filter(c=>c.track===chosen.trackNumber);
  if(cues.length!==expected||cues.some(c=>c.relativePosition===undefined)||new Set(cues.map(c=>c.clusterPosition+':'+c.relativePosition)).size!==expected)throw Error('frames_'+expected+'_'+cues.length);
  // Upstream targeted reads assume equal cluster header lengths. Verify it.
  const headerSizes=new Map               ();let next=0;
  const positions=Array.from(new Set(cues.map(c=>c.clusterPosition)));
  async function verifyHeaders(){while(next<positions.length){
    const pos=positions[next++];
    const h=parseElementHeader(await reader.read(seg.segmentDataOffset+pos,12),0);
    if(h.id!==0x1F43B675||h.unknownSize)throw Error('cluster');
    headerSizes.set(pos,h.dataOffset);
  }}
  await Promise.all(Array.from({length:Math.min(4,positions.length)},verifyHeaders));
  const blocks=await readTargetedBlocks(reader,seg.segmentDataOffset,cues,new Set([chosen.trackNumber]),seg.info.timestampScale,4,undefined,headerSizes);
  if(blocks.length!==expected||blocks.some(b=>!Number.isFinite(b.timestampMs)||b.timestampMs<0))throw Error('blocks_'+expected+'_'+blocks.length);
  const output=assembleAss(chosen,blocks);
  if(output.length>1048576)throw Error('limit');
  return {text:new TextDecoder().decode(output),frames:expected,bytes:reader.bytesDownloaded,requests:reader.requestCount};
}

exports.indexedASS=indexedASS;
}};const cache={};function require(id){if(cache[id])return cache[id];const e={};cache[id]=e;modules[id](require,e);return e;}global.CastMKV=require("bridge.ts");})(globalThis);
