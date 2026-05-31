package;

import lime.app.Application;
import lime.graphics.RenderContext;
import lime.ui.KeyCode;
import lime.ui.KeyModifier;
import lime.utils.Assets;
import openfl.display.Sprite;
import openfl.display.StageScaleMode;
import openfl.display.StageAlign;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.Lib;

import snes.Bus;
import snes.CPU;
import snes.PPU;
import snes.APU;
import snes.DMA;
import snes.Cartridge;
import snes.Controller;
import snes.Screen;

class Main extends Sprite {
    static inline final MASTER_CLOCK_NTSC:Float = 21477272.0;
    static inline final CYCLES_PER_FRAME:Int = 357366;
    static inline final SCREEN_WIDTH:Int = 256;
    static inline final SCREEN_HEIGHT:Int = 224;
    static inline final SCALE:Int = 2;

    var bus:Bus;
    var cpu:CPU;
    var ppu:PPU;
    var apu:APU;
    var dma:DMA;
    var cartridge:Cartridge;
    var controller1:Controller;
    var controller2:Controller;
    var screen:Screen;

    var running:Bool = false;
    var paused:Bool = false;
    var cycleAccumulator:Int = 0;
    var frameCount:Int = 0;
    var fpsTimer:Float = 0.0;
    var currentFps:Int = 0;

    public function new() {
        super();

        if (stage != null) init();
        else addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
    }

    function onAddedToStage(e:Event):Void {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        init();
    }

    function init():Void {
        stage.scaleMode = StageScaleMode.NO_SCALE;
        stage.align = StageAlign.TOP_LEFT;
        stage.color = 0x000000;
        stage.frameRate = 60;

        initSystems();
        bindInput();

        screen.attachTo(this);

        addEventListener(Event.ENTER_FRAME, onEnterFrame);

        #if js
        setupFileDropJS();
        #end
    }

    function initSystems():Void {
        controller1 = new Controller();
        controller2 = new Controller();

        cartridge = new Cartridge();
        screen = new Screen(SCREEN_WIDTH, SCREEN_HEIGHT, SCALE);

        ppu = new PPU(screen);
        apu = new APU();
        dma = new DMA();
        bus = new Bus(cartridge, ppu, apu, dma, controller1, controller2);
        cpu = new CPU(bus);

        dma.setBus(bus);
        ppu.setBus(bus);
    }

    function bindInput():Void {
        stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
        stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
    }

    function onEnterFrame(e:Event):Void {
        if (!running || paused) return;

        var cyclesToRun:Int = CYCLES_PER_FRAME;

        while (cyclesToRun > 0) {
            var elapsed:Int = step();
            cyclesToRun -= elapsed;
        }

        screen.present();
        frameCount++;

        var now:Float = haxe.Timer.stamp();
        if (now - fpsTimer >= 1.0) {
            currentFps = frameCount;
            frameCount = 0;
            fpsTimer = now;
            updateTitle();
        }
    }

    inline function step():Int {
        if (dma.isActive()) {
            return dma.tick();
        }
        return cpu.tick();
    }

    function loadROM(bytes:haxe.io.Bytes):Void {
        reset();
        cartridge.load(bytes);
        bus.reset();
        cpu.reset();
        ppu.reset();
        apu.reset();
        dma.reset();
        running = true;
        updateTitle();
    }

    function reset():Void {
        running = false;
        paused = false;
        cycleAccumulator = 0;
        frameCount = 0;
        fpsTimer = 0.0;
        currentFps = 0;
    }

    function updateTitle():Void {
        var title = "SNPrism";
        if (cartridge.isLoaded()) {
            title += " - " + cartridge.getTitle();
            if (running) title += " [" + currentFps + " FPS]";
            if (paused) title += " [PAUSED]";
        }
        #if cpp
        cpp.vm.Gc.run(false);
        #end
        Lib.application.window.title = title;
    }

    function onKeyDown(e:KeyboardEvent):Void {
        switch (e.keyCode) {
            case 82: // R
                if (cartridge.isLoaded()) {
                    bus.reset();
                    cpu.reset();
                    ppu.reset();
                    apu.reset();
                    dma.reset();
                }

            case 80: // P
                paused = !paused;
                updateTitle();

            case 79: // O
                #if (cpp || hl)
                openFileDialog();
                #end

            case 70: // F
                toggleFullscreen();

            case 49: controller1.press(Controller.BTN_A);
            case 50: controller1.press(Controller.BTN_B);
            case 51: controller1.press(Controller.BTN_X);
            case 52: controller1.press(Controller.BTN_Y);
            case 53: controller1.press(Controller.BTN_L);
            case 54: controller1.press(Controller.BTN_R);
            case 13: controller1.press(Controller.BTN_START);
            case 8:  controller1.press(Controller.BTN_SELECT);
            case 38: controller1.press(Controller.BTN_UP);
            case 40: controller1.press(Controller.BTN_DOWN);
            case 37: controller1.press(Controller.BTN_LEFT);
            case 39: controller1.press(Controller.BTN_RIGHT);
        }
    }

    function onKeyUp(e:KeyboardEvent):Void {
        switch (e.keyCode) {
            case 49: controller1.release(Controller.BTN_A);
            case 50: controller1.release(Controller.BTN_B);
            case 51: controller1.release(Controller.BTN_X);
            case 52: controller1.release(Controller.BTN_Y);
            case 53: controller1.release(Controller.BTN_L);
            case 54: controller1.release(Controller.BTN_R);
            case 13: controller1.release(Controller.BTN_START);
            case 8:  controller1.release(Controller.BTN_SELECT);
            case 38: controller1.release(Controller.BTN_UP);
            case 40: controller1.release(Controller.BTN_DOWN);
            case 37: controller1.release(Controller.BTN_LEFT);
            case 39: controller1.release(Controller.BTN_RIGHT);
        }
    }

    function toggleFullscreen():Void {
        #if !js
        var win = Lib.application.window;
        win.fullscreen = !win.fullscreen;
        #end
    }

    #if (cpp || hl)
    function openFileDialog():Void {
        var filters = [{extension: "sfc,smc", description: "SNES ROM"}];
        lime.ui.FileDialog.open(function(path:String) {
            if (path != null) {
                var bytes = sys.io.File.getBytes(path);
                loadROM(bytes);
            }
        }, null, filters, "Open SNES ROM");
    }
    #end

    #if js
    function setupFileDropJS():Void {
        var canvas = js.Browser.document.querySelector("canvas");
        if (canvas == null) return;

        canvas.addEventListener("dragover", function(e:js.html.DragEvent) {
            e.preventDefault();
        });

        canvas.addEventListener("drop", function(e:js.html.DragEvent) {
            e.preventDefault();
            var file = e.dataTransfer.files.item(0);
            if (file == null) return;
            var reader = new js.html.FileReader();
            reader.onload = function(_) {
                var ab:js.html.ArrayBuffer = cast reader.result;
                var bytes = haxe.io.Bytes.ofData(ab);
                loadROM(bytes);
            };
            reader.readAsArrayBuffer(file);
        });
    }
    #end

    static function main():Void {
        Lib.current.addChild(new Main());
    }
}
