package funkin.game.stage;

import flixel.graphics.frames.FlxFramesCollection;
import flixel.graphics.frames.FlxFrame;
import openfl.display.BitmapData;
import flixel.util.FlxColor;
import flixel.system.FlxAssets.FlxGraphicAsset;
import animate.internal.RenderTexture;

import funkin.game.Stage.StageCharPos;
import funkin.game.Stage.StageCharPosInfo;
import funkin.backend.utils.XMLUtil;
import funkin.backend.scripting.Script;
import funkin.backend.scripting.events.stage.StageXMLEvent;
import funkin.backend.system.interfaces.IBeatReceiver;

import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.math.FlxMatrix;
import flixel.util.FlxSignal.FlxTypedSignal;
import flixel.util.FlxStringUtil; 
import flixel.util.FlxStringUtil.LabelValuePair;
import flixel.util.FlxDestroyUtil;

import flixel.system.FlxAssets.FlxShader;

import flixel.FlxSprite;
#if FLX_DEBUG
import flixel.FlxBasic;
#end

import haxe.xml.Access;
import hscript.IHScriptCustomBehaviour;

import openfl.display.BlendMode;
import openfl.geom.ColorTransform;

using StringTools;

class LayerGroup extends FlxTypedGroup<FlxSprite> {
	private final parentLayer:Layer;

	public function new(layer:Layer) {
		this.parentLayer = layer;
		super();
		memberAdded.add((spr) -> {
			if(spr is Layer)
				parentLayer.onAddLayer.dispatch(cast(spr, Layer)); // explicit cast just to be sure :3  - Jamextreme140
			else
				parentLayer.onAddSprite.dispatch(spr);

			parentLayer.updateHitbox();
		});
		memberRemoved.add((_) -> {
			parentLayer.updateHitbox();
		});
	}

	@:access(animate.internal.RenderTexture)
	@:access(flixel.FlxSprite)
	public function drawMembers(camera:FlxCamera, parentMatrix:FlxMatrix, ?transform:ColorTransform, ?blend:BlendMode, ?antialiasing:Bool, ?shader:FlxShader) {
		for(member in members) {

			if(member is Layer) {
				var layer:Layer = cast member;
				layer.drawLayer(camera);
			}
			else {
				member.drawComplex(camera);
			}
		}
	}
}

class Layer extends FlxSprite implements IBeatReceiver {

	/**
	 * The Stage Name
	 */
	public var name:String;

	/**
	 * The actual group which holds all sprites in the layer.
	 */
	public final group:LayerGroup;

	/**
	 * Signal that triggers whenever a sprite is added. Similar to `group.memberAdded`, except sprite specific.
	 */
	public final onAddSprite:FlxTypedSignal<FlxSprite -> Void> = new FlxTypedSignal();

	/**
	 * Signal that triggers whenever a layer is added. Similar to `group.memberAdded`, except layer specific.
	 */
	public final onAddLayer:FlxTypedSignal<Layer -> Void> = new FlxTypedSignal();

	/**
	 * Whether to internally use a render texture when drawing the stage layer.
	 * This flattens all of the sprites and subsequent layers into a single graphic, making effects such as alpha or shaders apply to
	 * the entire sprite instead of individual members of the group.
	 */
	public var useRenderTexture:Bool = false;
	private var _renderTexture:RenderTexture;
	private var _renderTextureDirty:Bool = true;

	/**
	 * Shortcut for `group.members`
	 */
	public var members(get, never):Array<FlxSprite>;

	/**
	 * Internal. Used for rendering
	 */
	private var _bounds:FlxRect = FlxRect.get();

	public function new(name:String = 'stage_layer', useRenderTexture:Bool = false) {
		super();
		this.name = name;
		this.useRenderTexture = useRenderTexture;
		group = new LayerGroup(this);
	}

	//region IBeatReceiver implementation
	public function beatHit(curBeat:Int) {
		for(m in members) if(m != null && m is IBeatReceiver) cast(m, IBeatReceiver).beatHit(curBeat);
	}
	public function stepHit(curStep:Int) {
		for(m in members) if(m != null && m is IBeatReceiver) cast(m, IBeatReceiver).stepHit(curStep);
	}
	public function measureHit(curMeasure:Int) {
		for(m in members) if(m != null && m is IBeatReceiver) cast(m, IBeatReceiver).measureHit(curMeasure);
	}
	//endregion
	
	private var stageSprites:Map<String, FlxSprite> = [];
	private var stageLayers:Map<String, Layer> = [];

	//region Stage Layer Management
	public function add(obj:FlxSprite):FlxSprite {
		if(!(obj is Layer)) return group.add(obj);

		var layer:Layer = cast obj;
		if (stageLayers.exists(layer.name)) 
			return stageLayers.get(layer.name);

		stageLayers.set(layer.name, layer);
		return group.add(layer);
	}

	public function insert(position:Int, obj:FlxSprite):FlxSprite {
		if(!(obj is Layer)) return group.insert(position, obj);

		var layer:Layer = cast obj;
		if (stageLayers.exists(layer.name)) 
			return stageLayers.get(layer.name);

		stageLayers.set(layer.name, layer);
		return group.insert(position, layer);
	}

	public function remove(obj:FlxSprite, splice:Bool = false):FlxSprite {
		if(!(obj is Layer)) return group.remove(obj, splice);

		var layer:Layer = cast obj;
		stageLayers.remove(layer.name);
		return group.remove(layer, splice);
	}
	//endregion

	//region Stage Sprite Management
	public function addSprite(name:String, spr:FlxSprite):FlxSprite {
		if (stageSprites.exists(name)) return spr;

		this.add(spr);
		stageSprites.set(name, spr);

		return spr;
	}

	public function insertSprite(index:Int, name:String, spr:FlxSprite):FlxSprite {
		if (stageSprites.exists(name)) return spr;

		this.insert(index, spr);
		stageSprites.set(name, spr);

		return spr;
	}

	public function removeSprite(name:String, splice:Bool = false):Bool {
		if (!stageSprites.exists(name)) return false;

		var spr:FlxSprite = stageSprites.get(name);
		
		this.remove(spr, splice);
		stageSprites.remove(name);
		
		return true;
	}

	public inline function getSprite(name:String):Null<FlxSprite> {
		return stageSprites.exists(name) ? stageSprites[name] : null;
	}

	public inline function getLayer(name:String):Null<Layer> {
		return stageLayers.exists(name) ? stageLayers[name] : null;
	}
	//endregion

	//region Drawing 

	// heavily based on flixel-animate.
	// shoutouts for MaybeMaru for the rendering method :3 - Jamextreme140

	private function checkRenderTexture():Bool {
		return useRenderTexture && (alpha != 1 || shader != null || (blend != null && blend != NORMAL));
	}

	override function set_alpha(value:Float) {
		value = FlxMath.bound(value, 0, 1);
		if(!checkRenderTexture() && this.alpha != value) 
			transformMembers((spr) -> {spr.alpha = value;});
		
		return this.alpha = value;
	}

	override function set_blend(blend:BlendMode) {
		if(!checkRenderTexture())
			transformMembers((spr) -> {spr.blend = blend;});

		return this.blend = blend;
	}

	override function draw() {
		/*
		if(!checkRenderTexture()) {
			//super.draw();
			group.draw();
			return;
		} 
		*/

		if (alpha <= 0.0 || Math.abs(scale.x) <= 0.0 || Math.abs(scale.y) <= 0.0)
			return;
		
		for(cam in #if (flixel >= "5.7.0") this.getCamerasLegacy() #else this.cameras #end) {
			if (!camera.visible || !camera.exists /*|| !isOnScreen(camera)*/) // TODO: ACTUAL OPTIMIZATION
				continue;

			drawLayer(cam);

			#if FLX_DEBUG
			FlxBasic.visibleCount++;
			#end
		}

		#if FLX_DEBUG
		if (FlxG.debugger.drawDebug)
			drawDebug();
		#end
	}

	private function drawLayer(cam:FlxCamera) {
		final willUseRenderTexture = checkRenderTexture();
		final matrix:FlxMatrix = _matrix;
		_matrix.identity();

		var bounds:FlxRect = _bounds;
		if (!willUseRenderTexture)
			_matrix.translate(-_bounds.x, -_bounds.y);

		prepareLayerMatrix(_matrix, camera, _bounds);

		#if !flash
		if (willUseRenderTexture) {
			renderLayer();
		}
		else 
		#end
		{
			group.drawMembers(cam, _matrix, colorTransform, blend, antialiasing, shaderEnabled ? shader : null);
		}
	}

	#if !flash
	private inline function renderLayer() {
		if (_renderTexture == null)
			_renderTexture = new RenderTexture(Math.ceil(_bounds.width), Math.ceil(_bounds.height));

		_renderTexture.init(Math.ceil(_bounds.width), Math.ceil(_bounds.height));
		_renderTexture.drawToCamera((camera, matrix) -> {
			matrix.translate(-_bounds.x, -_bounds.y);
			group.drawMembers(camera, _matrix, null, null, antialiasing, null);
			// timeline.draw(camera, matrix, null, null, antialiasing, null);
		});
		_renderTexture.render();

		// _renderTextureDirty = false;
		

		if (layer != null)
			layer.drawPixels(this, camera, _renderTexture.graphic.imageFrame.frame, framePixels, _matrix, colorTransform, blend, antialiasing,
				shaderEnabled ? shader : null);
		else
			camera.drawPixels(_renderTexture.graphic.imageFrame.frame, framePixels, _matrix, colorTransform, blend, antialiasing, shaderEnabled ? shader : null);
	}
	#end

	private function prepareLayerMatrix(matrix:FlxMatrix, camera:FlxCamera, bounds:FlxRect):Void
	{
		if (checkFlipX())
		{
			matrix.scale(-1, 1);
			matrix.translate(bounds.width, 0);
		}

		if (checkFlipY())
		{
			matrix.scale(1, -1);
			matrix.translate(0, bounds.height);
		}

		prepareDrawMatrix(matrix, camera);
	}

	private function prepareDrawMatrix(matrix:FlxMatrix, camera:FlxCamera):Void
	{
		matrix.translate(-origin.x, -origin.y);
		
		if (frameOffsetAngle != null && frameOffsetAngle != angle)
		{
			var angleOff = (frameOffsetAngle - angle) * flixel.math.FlxAngle.TO_RAD;
			var cos = Math.cos(angleOff);
			var sin = Math.sin(angleOff);
			// cos doesnt need to be negated
			_matrix.rotateWithTrig(cos, -sin);
			_matrix.translate(-frameOffset.x, -frameOffset.y);
			_matrix.rotateWithTrig(cos, sin);
		}
		else
			_matrix.translate(-frameOffset.x, -frameOffset.y);

		matrix.scale(scale.x, scale.y);
		
		if (angle != 0) {
			updateTrig();
			matrix.rotateWithTrig(_cosAngle, _sinAngle);
		}

		getScreenPosition(_point, camera).subtractPoint(offset).add(origin.x, origin.y);
		matrix.translate(_point.x, _point.y);

		if (isPixelPerfectRender(camera))
			preparePixelPerfectMatrix(matrix);
	}

	private inline function preparePixelPerfectMatrix(matrix:FlxMatrix):Void {
		matrix.tx = Math.floor(matrix.tx);
		matrix.ty = Math.floor(matrix.ty);
	}

	//endregion

	/**
	 * If false, it will check values of `x`, `y`, `width` and `height` of the members directly
	 * instead of checking on each axes. This is faster but under some circumstances, 
	 * it might not be 100% accurate.
	 */
	public var updateHitboxDirty:Bool = false;

	override function updateHitbox() {
		if(group.length == 0) return;
		if (updateHitboxDirty) {
			this.x = findMinX();
			this.y = findMinY();
			this.width = findMaxX() - x;
			this.height = findMaxY() - y;
		}
		else {
			var minX:Float = Math.POSITIVE_INFINITY;
			var minY:Float = Math.POSITIVE_INFINITY;

			var maxX:Float = Math.NEGATIVE_INFINITY;
			var maxY:Float = Math.NEGATIVE_INFINITY;

			for (obj in group.members) {
				if (!__shouldUpdateBounds(obj)) continue;
				if (obj.x < minX) minX = obj.x;
				if (obj.y < minY) minY = obj.y;
				if (obj.x + obj.width > maxX) maxX = obj.x + obj.width;
				if (obj.y + obj.height > maxY) maxY = obj.y + obj.height;
			}

			//_bounds.set(minX, minY, maxX - minX, maxY - minY);
			setPosition(minX, minY);
			setSize(maxX - minX, maxY - minY);
		}
		_bounds = this.getHitbox(_bounds);

		frameWidth = Std.int(_bounds.width);
		frameHeight = Std.int(_bounds.height);

		centerOrigin();
	}

	//region Methods From FlxSpriteGroup
	private function findMinX():Float {
		if(group.length == 0) return 0;
		var value = Math.POSITIVE_INFINITY;

		for(m in group.members) {
			if (!__shouldUpdateBounds(m)) continue;

			var minX:Float;
			if(m is Layer) minX = cast(m, Layer).findMinX();
			else minX = m.x;

			if (minX < value) value = minX;
		}

		return value;
	}

	private function findMaxX():Float {
		if(group.length == 0) return 0;
		var value = Math.NEGATIVE_INFINITY;

		for(m in group.members) {
			if (!__shouldUpdateBounds(m)) continue;

			var maxX:Float;
			if(m is Layer) maxX = cast(m, Layer).findMaxX();
			else maxX = m.x + m.width;

			if (maxX > value) value = maxX;
		}

		return value;
	}

	private function findMinY():Float {
		if(group.length == 0) return 0;
		var value = Math.POSITIVE_INFINITY;

		for(m in group.members) {
			if (!__shouldUpdateBounds(m)) continue;

			var minY:Float;
			if(m is Layer) minY = cast(m, Layer).findMinY();
			else minY = m.y;

			if (minY < value) value = minY;
		}

		return value;
	}

	private function findMaxY():Float {
		if(group.length == 0) return 0;
		var value = Math.NEGATIVE_INFINITY;

		for(m in group.members) {
			if (!__shouldUpdateBounds(m)) continue;

			var maxY:Float;
			if(m is Layer) maxY = cast(m, Layer).findMaxY();
			else maxY = m.y + m.height;

			if (maxY > value) value = maxY;
		}

		return value;
	}
	//endregion

	private inline function __shouldUpdateBounds(m:FlxSprite):Bool {
		return m != null && m.exists && m.alive;
	}

	override function destroy() {
		super.destroy();
		_bounds = FlxDestroyUtil.put(_bounds);
	}

	private function get_members():Array<FlxSprite> {
		return group.members;
	}

	private function transformMembers(func:FlxSprite -> Void) {
		group.forEach((spr) -> {
			func(spr);
		});
	}

	override public function toString():String {
		return '(Stage Layer) $name: ${FlxStringUtil.getDebugString([
			LabelValuePair.weak("x", x),
			LabelValuePair.weak("y", y),
			LabelValuePair.weak("width", width),
			LabelValuePair.weak("height", height),
		])}';
	}

	//region Disable graphics functionality
	/**
	 * This functionality isn't supported in layers
	 * @return this sprite group
	 */
	@:dox(hide) override public function loadGraphicFromSprite(Sprite:FlxSprite):FlxSprite
	{
		#if FLX_DEBUG
		throw "This function is not supported in FlxSpriteGroup";
		#end
		return this;
	}

	/**
	 * This functionality isn't supported in layers
	 * @return this sprite group
	 */
	@:dox(hide) override public function loadGraphic(Graphic:FlxGraphicAsset, Animated:Bool = false, Width:Int = 0, Height:Int = 0, Unique:Bool = false,
			?Key:String):FlxSprite
	{
		return this;
	}

	/**
	 * This functionality isn't supported in layers
	 * @return this sprite group
	 */
	@:dox(hide) override public function loadRotatedGraphic(Graphic:FlxGraphicAsset, Rotations:Int = 16, Frame:Int = -1, AntiAliasing:Bool = false,
			AutoBuffer:Bool = false, ?Key:String):FlxSprite
	{
		#if FLX_DEBUG
		throw "This function is not supported in FlxSpriteGroup";
		#end
		return this;
	}

	/**
	 * This functionality isn't supported in layers
	 * @return this sprite group
	 */
	@:dox(hide) override public function makeGraphic(Width:Int, Height:Int, Color:Int = FlxColor.WHITE, Unique:Bool = false, ?Key:String):FlxSprite
	{
		#if FLX_DEBUG
		throw "This function is not supported in FlxSpriteGroup";
		#end
		return this;
	}

	@:dox(hide) override function set_pixels(Value:BitmapData):BitmapData {return Value;}

	@:dox(hide) override function set_frame(Value:FlxFrame):FlxFrame{return Value;}

	@:dox(hide) override function get_pixels():BitmapData {return null;}

	/**
	 * This functionality isn't supported in layers
	 *
	 * @param   force   Whether the frame should also be recalculated if we're on a non-flash target
	 */
	@:dox(hide) override inline function calcFrame(RunOnCpp:Bool = false):Void{/* Nothing to do here */}

	/**
	 * This functionality isn't supported in layers
	 */
	@:dox(hide) override inline function resetHelpers():Void {}

	/**
	 * This functionality isn't supported in layers
	 */
	@:dox(hide) override public inline function stamp(Brush:FlxSprite, X:Int = 0, Y:Int = 0):Void {}

	@:dox(hide) override function set_frames(Frames:FlxFramesCollection):FlxFramesCollection {return Frames;}

	/**
	 * This functionality isn't supported in layers
	 */
	@:dox(hide) override inline function updateColorTransform():Void {}
	//endregion
}

/**
 * A class that handles loading a stage and putting the sprites into the state.
 * 
 * @author Jamextreme140 & ItsLJCool
**/
class Stage extends Layer {
	private static final DEFAULT_ATTRIBUTES:Array<String> = ["name", "startCamPosX", "startCamPosY", "zoom", "folder", "useRenderTexture"];

	private static inline function getDefaultPos(name:String):StageCharPosInfo {
		return switch(name) {
			case "boyfriend" | "bf" | "player": 
				{x: 770, y: 100, scroll: 1, flip: true};
			case "girlfriend" | "gf": 
				{x: 400, y: 130, scroll: 0.95, flip: false};
			case "dad" | "opponent": 
				{x: 100, y: 100, scroll: 1, flip: false};
			default: 
				{x: 0, y: 0, scroll: 1, flip: false};
		}
	}

	public final fileName:String;
	public final xmlFilePath:String;
	public final scriptFilePath:String;

	public var xmlFile:Access;

	public var script:Script;
	public var allowScripts:Bool = true;
	public var xmlImportedScripts:Array<XMLImportedScriptInfo> = [];
	
	public var defaultZoom:Float = 1.05;
	public var spritesParentFolder = "";
	public var extra:Map<String, String> = [];
	public var startCam:FlxPoint = FlxPoint.get();

	// Callbacks
	public var onStageScriptLoad:Script -> Void;
	public var onPostStageCreation:StageXMLEvent->Void;
	
	public var onPrepareInfo:Access -> XMLImportedScriptInfo;
	public var onRemoveInfo:Script -> Void;
	
	public var onXMLLoaded:(StageXMLEvent)->Array<Access> = null;
	public var onNodeInitalize:(Access)->Dynamic = null;
	public var onNodeLoaded:(Access, Dynamic)->Dynamic = null;
	public var onNodeFinished:(Access, Dynamic)->Void = null;
	public var onXMLPostLoaded:(Access, Access)->Access = null;

	public var onStartCamSet:FlxPoint -> Float -> Void;
	public var onRatingSet:Float->Float->FlxSprite;
	
	public var onStageDestroy:Stage -> Void;
	public var onSilentDestroy:Script -> Void;

	private var characterPosLookup:Map<String, StageCharPos> = [];

	public var hasLoaded:Bool = false;

	/**
	 * Sets the sprites in the script, so you can access them by the name.
	**/
	public function setStagesSprites(script:Script) {
		for (key=>ref in stageSprites) script.set(key, ref);
		for (key=>ref in stageLayers) script.set(key, ref);
	}

	public function new(stage:String, load:Bool = false) {
		super(stage);

		fileName = stage;
		xmlFilePath = Paths.xml('stages/$fileName');
		scriptFilePath = Paths.script('data/stages/$fileName');
		if (Assets.exists(xmlFilePath)) {
			try xmlFile = new Access(Xml.parse(Assets.getText(xmlFilePath)).firstElement())
			catch (e) Logs.trace('Couldn\'t load stage "$xmlFilePath": ${e.message}', ERROR);
		}

		if(load) loadStage();
	}

	private var stageEvent:StageXMLEvent;

	public function loadStage(loadAll:Bool = false):Void {
		if (hasLoaded) return;
		if (allowScripts) {
			script = Script.create(scriptFilePath);
			if (onStageScriptLoad != null) onStageScriptLoad(script);
			script.setParent(this);
			script.load();
			script.call("create");
			script.call("onStageLoad");

			onAddSprite.add((obj:FlxSprite) -> script.call("onAddSprite", [obj]));
			onAddLayer.add((layer:Layer) -> script.call("onAddLayer", [layer]));
		}

		if (xmlFile == null) {
			postLoadStage(null);
			return;
		}

		loadStartCam();

		this.name = xmlFile.getAtt("name").getDefault(fileName);
		this.useRenderTexture = xmlFile.has.useRenderTexture ? xmlFile.att.useRenderTexture == "true" : false;

		if (onStartCamSet != null) 
			onStartCamSet(startCam, defaultZoom);

		if (xmlFile.has.folder) {
			spritesParentFolder = xmlFile.att.folder;
			if (!spritesParentFolder.endsWith("/"))
				spritesParentFolder += "/";
		}

		// Load custom attributes
		loadCustomAttributes();

		var data:Access = new Access(Xml.parse(xmlFile.x.toString()));
		// streamlined way to tag that the sprites are from the group
		checkMemoryMode(data, loadAll);

		if (onXMLLoaded != null) {
			//stageEvent = EventManager.get(StageXMLEvent).recycle(this, xmlFile, data);
			//data = onXMLLoaded(stageEvent);
		}
		
		loadLayer(this, data);

		//postLoadStage(elems);
		script?.call("postCreate");
		script?.call("onPostStageLoad");
		hasLoaded = true;
	}

	@:dox(hide) private inline function __isExtensionNode(node:Access):Bool {
		return node.name == "use-extension" || node.name == "extension" || node.name == "ext";
	}

	//region Memory Mode Filtering
	@:dox(hide) private function checkMemoryMode(xml:Access, loadAll:Bool) {
		for(node in xml.elements) {
			switch(node.name) {
				case 'high-memory':
					if(Options.lowMemoryMode || !loadAll) {
						xml.x.removeChild(node.x);
						continue;
					}
				case 'low-memory':
					if(!Options.lowMemoryMode || !loadAll) {
						xml.x.removeChild(node.x);
						continue;
					}
				case 'layer':
					checkMemoryMode(node, loadAll); // recursive filter in layers
			}

			if (__isExtensionNode(node) && XMLImportedScriptInfo.shouldLoadBefore(node))
				if (onPrepareInfo != null) onPrepareInfo(node);
		}
	}
	//endregion

	private inline function loadStartCam() {
		startCam.x = Std.parseFloat(xmlFile.getAtt("startCamPosX")).getDefaultFloat(0);
		startCam.y = Std.parseFloat(xmlFile.getAtt("startCamPosY")).getDefaultFloat(0);
		defaultZoom = Std.parseFloat(xmlFile.getAtt("zoom")).getDefaultFloat(1.05);
	}

	private inline function loadCustomAttributes() {
		for (att in xmlFile.x.attributes())
			if (!DEFAULT_ATTRIBUTES.contains(att))
				extra.set(att, xmlFile.x.get(att));
	}

	private function loadLayer(layer:Layer, data:Access) {
		var i:Int = 0; // local index count for Character setting
		for(node in data.elements) {
			// If `onNodeInitalize` returns a valid value, then why waste time on checking other values, 
			// since we should only care about what the user sets it too. Optimizations be like:
			var sprite:Dynamic = (onNodeInitalize != null) ? onNodeInitalize(node) : null;
			if(sprite == null) {
				sprite = switch(node.name) {
					case 'layer':
						if (!node.has.name) continue;

						var layerName:String = node.att.name;
						var renderLayer:Bool = node.has.useRenderTexture ? node.att.useRenderTexture == "true" : false;
						var new_layer:Layer = new Layer(layerName, renderLayer);
						// recursive so it will allow nested layers
						script?.call("onLoadLayer", [new_layer]);

						loadLayer(new_layer, node);
						layer.add(new_layer);
					
						script?.call("onPostLoadLayer", [new_layer]);
						new_layer;
					case "sprite" | "spr" | "sparrow":
						if (!node.has.name) continue;

						var spr = XMLUtil.createSpriteFromXML(node, spritesParentFolder, LOOP);
						layer.addSprite(spr.name, spr);
					case "box" | "solid":
						if (!node.has.name || !node.has.width || !node.has.height)
							continue;

						var isSolid = (node.name == "solid");

						var spr = new FunkinSprite();
						var w:Int = Std.parseInt(node.att.width);
						var h:Int = Std.parseInt(node.att.height);
						var c:flixel.util.FlxColor = (node.has.color) ? CoolUtil.getColorFromDynamic(node.att.color) : -1;
						if (isSolid)
						{
							spr.makeSolid(w, h, c);
							node.x.remove("updateHitbox");
						}
						else
							spr.makeGraphic(w, h, c);

						node.x.remove("width");
						node.x.remove("height");
						node.x.remove("color");
						XMLUtil.loadSpriteFromXML(spr, node, "", NONE, false);
						layer.addSprite(spr.name, spr);
					case "boyfriend" | "bf" | "player":
						setCharPos("boyfriend", node, getDefaultPos("boyfriend"), layer, i);
					case "girlfriend" | "gf":
						setCharPos("girlfriend", node, getDefaultPos("girlfriend"), layer, i);
					case "dad" | "opponent":
						setCharPos("dad", node, getDefaultPos("dad"), layer, i);
					case "character" | "char":
						if (!node.has.name)
							continue;
						setCharPos(node.att.name, node, null, layer, i);
					case "ratings" | "combo":
						if (onRatingSet == null)
							continue;
						onRatingSet(Std.parseFloat(node.getAtt("x")), Std.parseFloat(node.getAtt("y")));
					case 'high-memory' | 'low-memory':
						loadLayer(layer, node);
						null;
					default:
						// moved it to be like this, so we can just update the inline function - LJ
						if (__isExtensionNode(node))
						{
							if (XMLImportedScriptInfo.shouldLoadBefore(node))
								continue;
							if (onPrepareInfo != null && onPrepareInfo(node) == null)
								continue;
						}
						null;
				}
			}

			if (onNodeLoaded != null) {
				var _prevSprite = sprite;
				sprite = onNodeLoaded(node, sprite);
				// cleanup since there will be a random sprite floating around in memory
				if (_prevSprite != sprite && _prevSprite != null) _prevSprite.destroy();
			}

			if (sprite != null) {
				i++;
				for (e in node.nodes.property)
					XMLUtil.applyXMLProperty(sprite, e);
			}

			if (onNodeFinished != null) {
				onNodeFinished(node, sprite);
			}
		}
	}

	private function postLoadStage(?data:Array<Access>) {
		for(defaultChar in ["girlfriend", "dad", "boyfriend"]) {
			if (!characterPosLookup.exists(defaultChar))
				setCharPos(defaultChar, null, getDefaultPos(defaultChar), this);
		}

		if (allowScripts) {
			setStagesSprites(this.script);

			// i know this for gets run twice under, but its better like this in case a script modifies the short lived ones, i dont wanna save them in an array; more dynamic like this  - Nex
			for (info in xmlImportedScripts) if (info.importStageSprites) {
				var scriptInfo = info.getScript();
				if (scriptInfo != null) setStagesSprites(scriptInfo);
			}

			// idk lemme check anyways just in case scripts did smth  - Nex
			if(onPostStageCreation != null && stageEvent != null)
				onPostStageCreation(stageEvent);

			// shortlived scripts destroy when the stage finishes setting up  - Nex
			for (info in xmlImportedScripts) if (info.shortLived) {
				var scriptInfo = info.getScript();
				if (scriptInfo == null) continue;

				if (onRemoveInfo != null) onRemoveInfo(scriptInfo);
				scriptInfo.destroy();
			}
		}

		if (xmlFile != null && onXMLPostLoaded != null) {
			//data = onXMLPostLoaded(xmlFile, data);
		}
	}

	private function setCharPos(name:String, ?node:Access, ?defaultCharPos:StageCharPosInfo, layer:Layer, index:Int = -1) {
		var charPos = new StageCharPos();
		charPos.visible = charPos.active = false;
		charPos.name = name;

		if (defaultCharPos != null) {
			charPos.setPosition(defaultCharPos.x, defaultCharPos.y);
			charPos.scrollFactor.set(defaultCharPos.scroll, defaultCharPos.scroll);
			charPos.flipX = defaultCharPos.flip;
		}

		if (node != null) {
			charPos.x = Std.parseFloat(node.getAtt("x")).getDefaultFloat(charPos.x);
			charPos.y = Std.parseFloat(node.getAtt("y")).getDefaultFloat(charPos.y);

			charPos.charSpacingX = Std.parseFloat(node.getAtt("spacingx")).getDefaultFloat(charPos.charSpacingX);
			charPos.charSpacingY = Std.parseFloat(node.getAtt("spacingy")).getDefaultFloat(charPos.charSpacingY);

			charPos.camxoffset = Std.parseFloat(node.getAtt("camxoffset")).getDefaultFloat(charPos.camxoffset);
			charPos.camyoffset = Std.parseFloat(node.getAtt("camyoffset")).getDefaultFloat(charPos.camyoffset);

			charPos.skewX = Std.parseFloat(node.getAtt("skewx")).getDefaultFloat(charPos.skewX);
			charPos.skewY = Std.parseFloat(node.getAtt("skewy")).getDefaultFloat(charPos.skewY);

			charPos.alpha = Std.parseFloat(node.getAtt("alpha")).getDefaultFloat(charPos.alpha);
			charPos.angle = Std.parseFloat(node.getAtt("angle")).getDefaultFloat(charPos.angle);
			charPos.flipX = (node.has.flip || node.has.flipX) ? (node.getAtt("flip") == "true" || node.getAtt("flipX") == "true") : charPos.flipX;
			charPos.zoomFactor = Std.parseFloat(node.getAtt("zoomfactor")).getDefaultFloat(charPos.zoomFactor);

			// Scaling
			if (node.has.scale) {
				var scale:Float = Std.parseFloat(node.att.scale).getDefaultFloat(1);
				charPos.scale.set(scale, scale);
			}
			if (node.has.scalex) charPos.scale.x = Std.parseFloat(node.att.scalex).getDefaultFloat(1);
			if (node.has.scaley) charPos.scale.y = Std.parseFloat(node.att.scaley).getDefaultFloat(1);

			// Scroll Factor
			if (node.has.scroll) {
				var scroll:Float = Std.parseFloat(node.att.scroll).getDefaultFloat(1);
				charPos.scrollFactor.set(scroll, scroll);
			}
			if (node.has.scrollx) charPos.scrollFactor.x = Std.parseFloat(node.att.scrollx).getDefaultFloat(1);
			if (node.has.scrolly) charPos.scrollFactor.y = Std.parseFloat(node.att.scrolly).getDefaultFloat(1);
		}

		charPos.layer = layer;
		charPos.position = index;
		return characterPosLookup[name] = charPos;//layer.add(characterPosLookup[name] = charPos);
	}

	/**
	 * Checks if a character is flipped or not.
	 * @param posName The name of the character position
	 * @param def The default value
	**/
	public inline function isCharFlipped(posName:String, isPlayer:Bool = false)
		return characterPosLookup.exists(posName) ? characterPosLookup[posName].flipX : isPlayer;

	/**
	 * Applies the character position to the character.
	 * @param char The character to apply the position to.
	 * @param posName The name of the character position.
	 * @param id ?????? no fucking clue why does it have an ID it's never used!!!!!!!!!!!!!!!!
	**/
	public function applyCharPos(char:Character, posName:String, id:Float = 0) {
		var charName:String = char.curCharacter;
		var charPos:Null<StageCharPos> = characterPosLookup.exists(charName) ? characterPosLookup.get(charName) : characterPosLookup.get(posName);
		if(charPos != null && charPos.position != -1) {
			charPos.prepareCharacter(char, id);
			// allows setting characters in different layers
			// their position (index) is relative to their layer - Jamextreme140
			var layerRef:Layer = charPos.layer;
			layerRef.insert(charPos.position, char);
		}
		else 
			this.add(char);
	}

	override function update(elapsed:Float) {
		script?.call("update", [elapsed]);
		super.update(elapsed);
		script?.call("postUpdate", [elapsed]);
	}

	override function draw() {
		script?.call("draw");
		super.draw();
		script?.call("postDraw");
	}

	/**
	 * Same of destroy, but doesn't call the various script events.
	 * @param destroySprites Whether the stage sprites should be destroyed
	 * @param destroyScript Whether the stage script should be destroyed
	**/
	public function destroySilently(destroySprites:Bool = true, destroyScript:Bool = true) {
		if (destroyScript && script != null) {
			if (onSilentDestroy != null) onSilentDestroy(this.script);
			script.destroy();
		}

		startCam.put();
		
		// Properly destroy the sprites here.
		super.destroy();
	}

	override function destroy() {
		if (onStageDestroy != null) onStageDestroy(this);
		script?.call("destroy");
		destroySilently();
	}

	// Backwards compatibility
	public var stagePath(get, never):String;
	public var stageFile(get, never):String;
	public var stageName(get, set):String;
	public var stageScript(get, never):Script;
	public var characterPoses(get, never):Map<String, StageCharPos>;

	function get_stageScript():Script { return this.script; }
	function get_stagePath():String { return this.xmlFilePath; }
	function get_stageFile():String { return this.fileName; }
	function get_stageName():String { return this.name; }
	function set_stageName(name:String):String { return this.name = name; }
	function get_characterPoses():Map<String, StageCharPos> { return this.characterPosLookup; }
	inline function applyCharStuff(char:Character, posName:String, id:Float = 0) { return applyCharPos(char, posName, id); }
}

class StageCharPos extends FlxObject {
	public var extra:Map<String, Dynamic> = [];

	public var name:String;
	public var layer:Layer;
	public var position:Int = -1;
	public var charSpacingX:Float = 20;
	public var charSpacingY:Float = 0;
	public var camxoffset:Float = 0;
	public var camyoffset:Float = 0;
	public var skewX:Float = 0;
	public var skewY:Float = 0;
	public var alpha:Float = 1;
	public var flipX:Bool = false;
	public var scale:FlxPoint = FlxPoint.get(1, 1);
	public var zoomFactor:Float = 1;

	public function new() {
		super();
		active = false;
		visible = false;
	}

	public override function destroy() {
		scale.put();
		super.destroy();
	}

	private var _id:Float = -1;

	private var oldInfo:OldCharInfo = null;

	public function prepareCharacter(char:Character, id:Float = 0) {
		_id = id;
		oldInfo = getOldInfo(char);
		char.setPosition(x + (id * charSpacingX), y + (id * charSpacingY));
		char.scrollFactor.set(scrollFactor.x, scrollFactor.y);
		if (!Std.isOfType(FlxG.state, funkin.editors.character.CharacterEditor)) {
			char.scale.x *= scale.x; char.scale.y *= scale.y;
		}
		char.cameraOffset += FlxPoint.weak(camxoffset, camyoffset);
		char.skew.x += skewX; char.skew.y += skewY;
		char.alpha *= alpha;
		char.angle += angle;
		char.zoomFactor *= zoomFactor;
	}

	public function getOldInfo(char:Character) {
		return {
			x: char.x, y: char.y,
			scrollX: char.scrollFactor.x, scrollY: char.scrollFactor.y,
			scaleX: char.scale.x, scaleY: char.scale.y,
			camxoffset: char.cameraOffset.x, camyoffset: char.cameraOffset.y,
			skewX: char.skew.x, skewY: char.skew.y,
			alpha: char.alpha, zoomFactor: char.zoomFactor,
			angle: char.angle
		}
	}

	public function revertCharacter(char:Character) {
		if(oldInfo == null) return;
		for(field in Reflect.fields(oldInfo)) {
			switch(field) {
				case "scrollX": char.scrollFactor.x = oldInfo.scrollX;
				case "scrollY": char.scrollFactor.y = oldInfo.scrollY;
				case "scaleX": char.scale.x = oldInfo.scaleX;
				case "scaleY": char.scale.y = oldInfo.scaleY;
				case "camxoffset": char.cameraOffset.x = oldInfo.camxoffset;
				case "camyoffset": char.cameraOffset.y = oldInfo.camyoffset;
				case "skewX": char.skew.x = oldInfo.skewX;
				case "skewY": char.skew.y = oldInfo.skewY;
				default: Reflect.setProperty(char, field, Reflect.field(oldInfo, field));
			}
		}
		oldInfo = null;
	}
}
typedef StageCharPosInfo = {
	var x:Float;
	var y:Float;
	var flip:Bool;
	var scroll:Float;
}

typedef OldCharInfo = {
	var x:Float;
	var y:Float;
	var scrollX:Float;
	var scrollY:Float;
	var scaleX:Float;
	var scaleY:Float;
	var camxoffset:Float;
	var camyoffset:Float;
	var skewX:Float;
	var skewY:Float;
	var alpha:Float;
	var zoomFactor:Float;
	var angle:Float;
}
