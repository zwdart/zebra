use std::io::Read;
use brotli::Decompressor;

const MAGIC: &[u8] = b"ZEBRA";

pub struct PackedFile {
    pub path: String,
    pub kind: u8, // 0 = 普通文件, 1 = 符号链接(data 为链接目标)
    pub data: Vec<u8>,
}

pub struct BinaryReader {
    pub files: Vec<PackedFile>,
    pub exe: String,
}

impl BinaryReader {
    pub fn from_bytes(bytes: &[u8]) -> Self {
        let pos = bytes.windows(MAGIC.len()).position(|w| w == MAGIC);
        let start = pos.expect("No packed data found") + MAGIC.len();
        parse(&bytes[start..])
    }
}

fn parse(data: &[u8]) -> BinaryReader {
    let mut off = 0;
    let mut files = Vec::new();

    loop {
        if off + MAGIC.len() <= data.len() && &data[off..off + MAGIC.len()] == MAGIC {
            break;
        }
        let kind = data[off];
        off += 1;
        let plen = u32::from_be_bytes(data[off..off + 4].try_into().unwrap()) as usize;
        off += 4;
        let path = String::from_utf8(data[off..off + plen].to_vec()).unwrap();
        off += plen;
        let dlen = u32::from_be_bytes(data[off..off + 4].try_into().unwrap()) as usize;
        off += 4;
        let mut decoder = Decompressor::new(&data[off..off + dlen], 4096);
        let mut buf = Vec::new();
        decoder.read_to_end(&mut buf).unwrap();
        off += dlen;
        off += 16; // skip md5
        files.push(PackedFile { path, kind, data: buf });
    }

    off += MAGIC.len();
    let elen = u32::from_be_bytes(data[off..off + 4].try_into().unwrap()) as usize;
    off += 4;
    let exe = String::from_utf8(data[off..off + elen].to_vec()).unwrap();

    BinaryReader { files, exe }
}
