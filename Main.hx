import haxe.io.BytesInput;
import js.html.Blob;
import js.html.Event;
import js.html.InputElement;
import js.html.ImageElement;
import js.html.Document;
import js.lib.Promise;
import js.html.Element;
import ASCII.ASCIIData;
import ASCII.CharsetData;
import js.lib.ArrayBuffer;
import haxe.io.Bytes;
import js.html.DragEvent;
import js.html.File;

class Main extends hxd.App {
    static var doc:Document;
    static var body:Element;
    static var tip:Element;
    static var fileInput:InputElement;
    static var output:ImageElement;

    var art:ASCIIData = null;
    var charset:CharsetData = null;
    var tileset:h2d.Tile = null;
    var tiles:Array<h2d.Tile>;
    var palette:Array<Int> = null;
    
    static function main() {
        #if js
        doc = js.Browser.document;
        tip = doc.getElementById("tip");
        body = doc.getElementsByTagName("body")[0];
        fileInput = cast doc.getElementById("finput");
        output = cast doc.getElementById("output");
        #end

        new Main();
    }

    override function init() {
        engine.autoResize = false;
        //TODO: non-js implementation
        #if js
        body.ondragover = (e:DragEvent) -> {
            e.preventDefault();
        };
        body.ondrop = (e:DragEvent) -> {
            e.preventDefault();
            var files = [];
            if (e.dataTransfer.items == null) {
                for (f in e.dataTransfer.items)
                    files.push(f.getAsFile());
            } else {
                for (f in e.dataTransfer.files)
                    files.push(f);
            }

            handleFiles(files);
        };

        fileInput.onchange = (e:Event) -> {
            var files = [for (i in 0...fileInput.files.length) fileInput.files.item(i)];
            handleFiles(files);
            e.preventDefault();
        };
        #end
        
        present();
    }

    function handleFiles(files:Array<File>) {
        for (f in files) {
            if (f.type == "image/png" || f.name.substring(f.name.lastIndexOf('.')) == ".char") {
                if (charset == null || tileset == null) {
                    if (f.type == "image/png" && f.name == art.charsetName + ".png") {
                        handleTileset(f);
                    } else if (f.name == art.charsetName + ".char") {
                        handleCharset(f, ()->{});
                    }
                } else if (f.type == "image/png" && f.name == art.paletteName + ".png") {
                    handlePalette(f);
                }
            } else {
                handleArt(f);
            }
        }
    }

    function present() {
        tip.textContent = "Drag-and-Drop a .3dscii file into this window or select it via form below to load it";
        if (art == null) {
            return;
        }

        var pending = false;
        var text = "Now upload these charset files:\n";

        if (charset == null) {
            pending = true;
            text += art.charsetName + ".char\n";
        }

        if (tileset == null) {
            pending = true;
            text += art.charsetName + ".png\n";
        }

        if (pending) {
            tip.textContent = text;
            return;
        }

        if (palette == null) {
            tip.textContent =
                "Now upload this palette file:\n" + 
                art.paletteName + ".png";
            return;
        }

        var cw = Std.int(tileset.width / charset.width);
        var ch = Std.int(tileset.height / charset.height);
        tiles = [
            for (y in 0...charset.width) {
                for (x in 0...charset.height) {
                    tileset.sub(x * cw, y * ch, cw, ch, -cw / 2, -ch / 2);
                }
            }
        ];

        draw();
        tip.textContent = "Done! You can Right-click the Image to Save it and/or Copy it to Clipboard";
    }

    override function mainLoop() {}

    function draw() {
        var tg = new h2d.TileGroup(tileset, s2d);
        tg.addShader(new ColorLookup([for (c in palette) h3d.Vector.fromColor(c)]));

        for (layer in art.layers) {
            var x = 0;
            var y = 0;
            for (cell in layer.cells) {
                var vIdx = cell.value < tiles.length ? cell.value : 0;
                var bgIdx = cell.bgColor < palette.length ? cell.bgColor : 0;
                var fgIdx = cell.fgColor < palette.length ? cell.fgColor : 0;

                var col = new h3d.Vector(1. / 255 * fgIdx, 1. / 255 * bgIdx, 0, 1);
                var xs = cell.xFlip ? -1 : 1;
                var ys = cell.yFlip ? -1 : 1;
                var rot = 0.;
                if (cell.dFlip) {
                    rot = -Math.PI / 2;
                    xs = -xs;
                }

                @:privateAccess tg.content.addTransform((0.5 + x) * tiles[0].width, (0.5 + y) * tiles[0].height, xs, ys, rot, col, tiles[vIdx]);

                x++;
                if (x >= art.width) {
                    y++;
                    x = 0;
                }
            }
        }

        var win = hxd.Window.getInstance();
        var canvas = @:privateAccess win.canvas;
        
        var w = Std.int(tiles[0].width * art.width);
        var h = Std.int(tiles[0].height * art.height);
        engine.driver.resize(w, h);
        @:privateAccess engine.width = w;
        @:privateAccess engine.height = h;
        canvas.style.width = '${w}px';
        canvas.style.height = '${h}px';

        engine.clear(0, 0, 0);
        s2d.render(engine);

        tg.remove();

        var dataURL = canvas.toDataURL("image/png");
        output.src = dataURL;
        output.style.display = "initial";
    }

    function lookup(url:String, cb:Blob->Void) {
        js.Browser.window.fetch(url)
            .catchError((err) -> {cb(null);})
            .then((resp:js.html.Response) -> {
                if (resp.ok) {
                    resp.blob().then((blob) -> {
                        cb(blob);
                    });
                } else {
                    cb(null);
                }
            });
    }

    function handleArt(file:Blob) {
        charset = null;
        tileset = null;
        tiles = null;
        palette = null;

        var promise:Promise<ArrayBuffer> = js.Syntax.code("{0}.arrayBuffer()", file);
        promise.then((buf) -> {
            var data = Bytes.ofData(buf);
            try {
                art = ASCII.parse(new haxe.io.BytesInput(data, 0, data.length));
                
                lookup('charsets/${art.charsetName}.char', (blob) -> {
                    if (blob != null) {
                        handleCharset(blob, () -> {
                            if (charset != null) {
                                lookup('charsets/${charset.tilesetName}', (blob) -> {
                                    if (blob != null)
                                        handleTileset(blob);
                                });
                            }
                        });
                    }
                });

                lookup('palettes/${art.paletteName}.png', (blob) -> {
                    if (blob != null)
                        handlePalette(blob);
                });

                present();
            } catch (err:Dynamic) {
                tip.textContent = err;
                throw err;
            }
        });
    }

    function handleTileset(file:Blob) {
        var promise:Promise<ArrayBuffer> = js.Syntax.code("{0}.arrayBuffer()", file);
        promise.then((buf) -> {
            var data = Bytes.ofData(buf);
            var res = hxd.res.Any.fromBytes('/charsets/${art.charsetName}.png', data);
            tileset = res.toImage().toTile();

            present();
        });
    }

    function handleCharset(file:Blob, cb:Void->Void) {
        var promise:Promise<ArrayBuffer> = js.Syntax.code("{0}.arrayBuffer()", file);
        promise.then((buf) -> {
            var data = Bytes.ofData(buf);
            charset = ASCII.readCharset(new haxe.io.BytesInput(data, 0, data.length));
            cb();

            present();
        });
    }

    function handlePalette(file:Blob) {
        var promise:Promise<ArrayBuffer> = js.Syntax.code("{0}.arrayBuffer()", file);
        promise.then((buf) -> {
            var data = Bytes.ofData(buf);
            var res = hxd.res.Any.fromBytes('/palettes/${art.paletteName}.png', data);

            // heaps doesn't support some png formats
            // we'll handle the palette pngs manually
            var chunks = new format.png.Reader(new BytesInput(data, 0, data.length)).read();
                
            // png has embedded palette - but we can't use it!
            // because it may have the colors in incorrect order
            var pixels = format.png.Tools.extract32(chunks);
            palette = [0];
            var pos = 0;
            while (pos < pixels.length) {
                var b = pixels.get(pos++);
                var g = pixels.get(pos++);
                var r = pixels.get(pos++);
                var a = pixels.get(pos++);

                var v = a << 24 | r << 16 | g << 8 | b;
                if (palette.indexOf(v) == -1)
                    palette.push(v);
            }

            present();
        });
    }
}

class ColorLookup extends hxsl.Shader {
    public function new(palette) {
        super();
        this.palette = palette;
    }
    static var SRC = {
        @:import h3d.shader.Base2d;
        @borrow(h3d.shader.Base2d) var texture:Sampler2D;
        
        @param var palette:Array<Vec4, 256>;
        function fragment() {
            var index = (input.color * 255.).rg;
            var tex = texture.get(calculatedUV);
            if (tex.r > 0) {
                pixelColor = palette[int(index.r)];
            } else {
                pixelColor = palette[int(index.g)];
            }
        }
    };
}