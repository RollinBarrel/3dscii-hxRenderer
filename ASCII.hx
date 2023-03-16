import haxe.io.BytesInput;
import haxe.io.Bytes;

typedef CharsetData = {
    var tilesetName:String;
    var width:Int;
    var height:Int;
};

typedef CellData = {
    var value:Int;
    var fgColor:Int;
    var bgColor:Int;
    var xFlip:Bool;
    var yFlip:Bool;
    var dFlip:Bool;
    var invColors:Bool;
}

typedef LayerData = {
    var name:String;
    var depthOffset:Float;
    var cells:Array<CellData>;
    var alpha:Float;
    var visible:Bool;
}

typedef ASCIIData = {
    var rev:Int;
    var name:String;
    var width:Int;
    var height:Int;
    var charsetName:String;
    var paletteName:String;
    var layers:Array<LayerData>;
}

class ASCII {
    // public static function serialize(data:ASCIIData):Bytes {}
    public static function parse(b:haxe.io.Input):ASCIIData {
        if (b.readString(6) != "3DSCII")
            throw 'No "3DSCII" found in file header';

        var rev = b.readUInt16();
        // handle previous revisions
        switch (rev) {
            case 4:
            default:
                throw "Unsupported revision: " + rev;
        }

        var name = b.readString(b.readByte());
        var width = b.readByte();
        var height = b.readByte();
        var charsetName = b.readString(b.readByte());
        var paletteName = b.readString(b.readByte());

        var layerCount = b.readByte();
        var layers = [];
        for (l in 0...layerCount) {
            var layerName = b.readString(b.readByte());
            var depthOffset = b.readFloat();
            var alpha = b.readFloat();

            var flags = b.readByte();
            var visible = (flags & 1 << 0) > 0;

            var layer:LayerData = {
                name: layerName,
                depthOffset: depthOffset,
                cells: [],
                alpha: alpha,
                visible: visible
            };
            layer.cells.resize(width * height);

            for (c in 0...width * height) {
                var value = b.readUInt16();
                var fgColor = b.readByte();
                var bgColor = b.readByte();

                var flags = b.readByte();
                var xFlip = flags & (1 << 0) > 0;
                var yFlip = flags & (1 << 1) > 0;
                var dFlip = flags & (1 << 2) > 0;
                var invColors = flags & (1 << 3) > 0;
                layer.cells[c] = {
                    value: value,
                    fgColor: fgColor,
                    bgColor: bgColor,
                    xFlip: xFlip,
                    yFlip: yFlip,
                    dFlip: dFlip,
                    invColors: invColors
                };
            }

            layers.push(layer);
        }

        return {
            rev: rev,
            name: name,
            width: width,
            height: height,
            charsetName: charsetName,
            paletteName: paletteName,
            layers: layers
        };
    }

    public static function readCharset(b:haxe.io.Input):CharsetData {
        var state = 0;
        var tilesetName = "";
        var width = 0;
        var height = 0;
        try {
            while (true) {
                var line = b.readLine();
                if (line.substr(0, 2) == "//")
                    continue;

                switch (state) {
                    case 0:
                        tilesetName = line;
                        state++;
                    case 1:
                        width = Std.parseInt(line.substring(0, line.indexOf(',')));
                        height = Std.parseInt(line.substring(line.indexOf(',') + 1));
                        state++;
                    case 2:
                        //TODO: parse characters
                }
            }
        } catch (eof:haxe.io.Eof) {}

        return {
            tilesetName: tilesetName,
            width: width,
            height: height
        };
    }
}