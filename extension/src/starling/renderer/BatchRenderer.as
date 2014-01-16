/**
 * User: booster
 * Date: 14/01/14
 * Time: 13:48
 */
package starling.renderer {
import com.barliesque.agal.EasierAGAL;
import com.barliesque.agal.IComponent;
import com.barliesque.agal.IRegister;

import flash.display3D.Context3D;
import flash.display3D.Context3DProgramType;
import flash.display3D.Context3DVertexBufferFormat;

import flash.display3D.IndexBuffer3D;

import flash.display3D.VertexBuffer3D;
import flash.errors.IllegalOperationError;
import flash.geom.Matrix;
import flash.geom.Matrix3D;
import flash.geom.Matrix3D;

import starling.core.Starling;
import starling.errors.MissingContextError;

import starling.renderer.constant.ComponentConstant;
import starling.renderer.constant.ConstantType;
import starling.renderer.constant.ConstantType;
import starling.renderer.constant.RegisterConstant;
import starling.renderer.vertex.VertexFormat;

import starling.textures.Texture;
import starling.utils.MatrixUtil;

public class BatchRenderer extends EasierAGAL {
    private static var _projectionMatrix:Matrix             = new Matrix();
    private static var _matrix3D:Matrix3D                   = new Matrix3D();
    private static var _vertexConstants:Vector.<Number>     = new <Number>[];
    private static var _fragmentConstants:Vector.<Number>   = new <Number>[];

    private var _inputTextures:Vector.<Texture>     = new <Texture>[];
    private var _inputTextureNames:Vector.<String>  = new <String>[];
    private var _outputTexture:Texture              = null;

    private var _vertexBuffer:VertexBuffer3D        = null;
    private var _indexBuffer:IndexBuffer3D          = null;
    private var _buffersDirty:Boolean               = false;

    // vertex specific variables will be changed to VertexData once it's ready for customisation
    private var _vertexRawData:Vector.<Number>      = new <Number>[];
    private var _vertexFormat:VertexFormat          = null;
    private var _triangleData:Vector.<int>          = new <int>[];

    private var _registerConstants:Vector.<RegisterConstant>      = new <RegisterConstant>[];
    private var _componentConstants:Vector.<ComponentConstant>    = new <ComponentConstant>[];

    private var _currentProgramType:int;

    public function getInputTextureIndex(name:String):int { return _inputTextureNames.indexOf(name); }

    public function getInputTexture(name:String):Texture {
        var index:int = getInputTextureIndex(name);

        return index >= 0 ? _inputTextures[index] : null;
    }

    public function setInputTexture(name:String, texture:Texture):void {
        var index:int = getInputTextureIndex(name);

        if(index >= 0) {
            if(texture == null) {
                _inputTextures.splice(index, 1);
                _inputTextureNames.splice(index, 1);
            }
            else {
                _inputTextures[index] = texture;
            }
        }
        else if(texture != null) {
            _inputTextures[_inputTextures.length]           = texture;
            _inputTextureNames[_inputTextureNames.length]   = name;
        }
    }

    public function get outputTexture():Texture { return _outputTexture; }
    public function set outputTexture(value:Texture):void { _outputTexture = value; }

    // also erases all vertices
    public function setVertexFormat(format:VertexFormat):void {
        _vertexRawData.length   = 0;
        _triangleData.length    = 0;
        _vertexFormat           = format;
    }

    public function get vertexCount():int { return _vertexRawData.length / _vertexFormat.totalSize; }

    // returns first newly added vertex index
    public function addVertices(count:int):int {
        var firstIndex:int      = vertexCount - 1;
        _vertexRawData.length  += _vertexFormat.totalSize * count;

        return firstIndex;
    }

    public function addTriangle(v1:int, v2:int, v3:int):void {
        _triangleData[_triangleData.length] = v1;
        _triangleData[_triangleData.length] = v2;
        _triangleData[_triangleData.length] = v3;
    }

    public function getVertexData(vertex:int, id:int, data:Vector.<Number> = null):Vector.<Number> {
        var index:int   = _vertexFormat.totalSize * vertex + _vertexFormat.getOffset(id);
        var size:int    = _vertexFormat.getSize(id);

        if(data == null) data = new Vector.<Number>(size);

        for(var i:int = 0; i < size; ++i)
            data[i] = _vertexRawData[index + i];

        return data;
    }

    public function setVertexData(vertex:int, id:int, x:Number, y:Number = NaN, z:Number = NaN, w:Number = NaN):void {
        var index:int   = _vertexFormat.totalSize * vertex + _vertexFormat.getOffset(id);
        var size:int    = _vertexFormat.getSize(id);

        //noinspection FallthroughInSwitchStatementJS
        switch(size) {
            case 4: _vertexRawData[index + 3] = w;
            case 3: _vertexRawData[index + 2] = z;
            case 2: _vertexRawData[index + 1] = y;
            case 1: _vertexRawData[index    ] = x;
                break;

            default:
                throw new Error("vertex data size invalid (" + size + "for vertex: " + vertex + ", data id: " + id);
        }
    }

    public function addRegisterConstant(name:String, type:int, x:Number, y:Number, z:Number, w:Number):void {
        _registerConstants[_registerConstants.length] = new RegisterConstant(name, type, x, y, z, w);
    }

    public function addComponentConstant(name:String, type:int, value:Number):void {
        _componentConstants[_componentConstants.length] = new ComponentConstant(name, type, value);
    }

    public function removeRegisterConstant(name:String, type:int):void {
        var index:int = getRegisterConstantIndex(name, type);

        if(index < 0) return;

        _registerConstants.splice(index, 1);
    }

    public function removeComponentConstant(name:String, type:int, value:Number):void {
        var index:int = getComponentConstantIndex(name, type);

        if(index < 0) return;

        _componentConstants.splice(index, 1);
    }

    public function modifyRegisterConstant(name:String, type:int, x:Number, y:Number, z:Number, w:Number):void {
        var index:int                   = getRegisterConstantIndex(name, type);
        var constant:RegisterConstant   = _registerConstants[index];

        constant.setValues(x, y, z, w);
    }

    public function modifyComponentConstant(name:String, type:int, value:Number):void {
        var index:int                   = getComponentConstantIndex(name, type);
        var constant:ComponentConstant  = _componentConstants[index];

        constant.value = value;
    }

    public function getRegisterConstantIndex(name:String, type:int):int {
        var count:int = _registerConstants.length;
        for(var i:int = 0; i < count; i++) {
            var constant:RegisterConstant = _registerConstants[i];

            if(type != constant.type || name != constant.name)
                continue;

            return i;
        }

        return -1;
    }

    public function getComponentConstantIndex(name:String, type:int):int {
        var count:int = _componentConstants.length;
        for(var i:int = 0; i < count; i++) {
            var constant:ComponentConstant = _componentConstants[i];

            if(type != constant.type || name != constant.name)
                continue;

            return i;
        }

        return -1;
    }

    public function render():void {
//        if(_output == null)
//            throw new UninitializedError("output texture must be set");
//
//        if(_input.root == _output.root)
//            throw new UninitializedError("input cannot be used as output");

        var context:Context3D = Starling.context;

        if(context == null)
            throw new MissingContextError();

//        var pma:Boolean = mVertexData.premultipliedAlpha;

        if(_buffersDirty)
            createBuffers();

        //sRenderAlpha[0] = sRenderAlpha[1] = sRenderAlpha[2] = pma ? alpha : 1.0;
        //sRenderAlpha[3] = alpha;

//        var rootWidth:Number  = _output.root.width;
//        var rootHeight:Number = _output.root.height;
//
//        if(clipRect == null)    _clipRect.setTo(0, 0, _output.width, _output.height);
//        else                    _clipRect.setTo(clipRect.x, clipRect.y, clipRect.width, clipRect.height);

        // render to output texture
        //_renderSupport.renderTarget = _output;
        if(_outputTexture != null)  context.setRenderToTexture(_outputTexture.base);
        else                        context.setRenderToBackBuffer();

        //if(clearOutput)
        //    _renderSupport.clear();
        context.clear();

        // setup output regions for rendering
        //_renderSupport.loadIdentity();
        //_renderSupport.setOrthographicProjection(0, 0, rootWidth, rootHeight);
//        _renderSupport.pushClipRect(_clipRect);
       var m:Matrix3D = setOrthographicProjection(0, 0, 800, 600);

        // set blend mode
//        _renderSupport.blendMode = blendMode;
//        _renderSupport.applyBlendMode(pma);

        // transform input
//        if(matrix != null)
//            _renderSupport.prependMatrix(matrix);

        // activate program (shader) and set the required buffers, constants, texture
        context.setProgram(upload(context));

        context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 0, m, true); //vc0

        setProgramConstants(context, 4, 0);

        //context.setTextureAt(0, _input.base); // fs0
        setInputTextures(context);

        //context.setVertexBufferAt(0, mVertexBuffer, VertexData.POSITION_OFFSET, Context3DVertexBufferFormat.FLOAT_2); // va0 - position
        //context.setVertexBufferAt(1, mVertexBuffer, VertexData.TEXCOORD_OFFSET, Context3DVertexBufferFormat.FLOAT_2); // va1 - UV

        //if(_passUVRangeInGeometry)
        //    context.setVertexBufferAt(2, mVertexBuffer, ExtendedVertexData.UV_RANGE_OFFSET, Context3DVertexBufferFormat.FLOAT_4); // va2 - UV range
        setVertexBuffers(context);

        // render
        //_shader.activate(context);
        context.drawTriangles(_indexBuffer, 0, _triangleData.length / 3);
        //_shader.deactivate(context);

        // reset buffers
        //context.setTextureAt(0, null);
        //context.setVertexBufferAt(0, null);
        //context.setVertexBufferAt(1, null);
        //if(_passUVRangeInGeometry)
        //    context.setVertexBufferAt(2, null);
        unsetInputTextures(context);
        unsetVertexBuffers(context);

//        _renderSupport.renderTarget = null;
//        _renderSupport.popClipRect();
    }

    protected function getRegisterConstant(name:String):IRegister {
        var index:int = 0;
        var count:int = _registerConstants.length;
        for(var i:int = 0; i < count; i++) {
            var constant:RegisterConstant = _registerConstants[i];

            if(_currentProgramType != constant.type)
                continue;

            if(name != constant.name) {
                ++index;
            }
            else {
                // first four vc registers are reserved for the transformation matrix
                return _currentProgramType == ConstantType.VERTEX ? CONST[index + 4] : CONST[index];
            }
        }

        return null;
    }

    protected function getComponentConstant(name:String):IComponent {
        var index:int = 0;
        var count:int = _componentConstants.length;
        for(var i:int = 0; i < count; i++) {
            var constant:ComponentConstant = _componentConstants[i];

            if(_currentProgramType != constant.type)
                continue;

            if(name != constant.name) {
                ++index;
            }
            else {
                var regIndex:int    = index / 4; // 4 components per register
                var compIndex:int   = index % 4;

                // first four vc registers are reserved for the transformation matrix
                if(_currentProgramType == ConstantType.VERTEX)
                    regIndex += 4;

                switch(compIndex) {
                    case 0: return CONST[regIndex].x;
                    case 1: return CONST[regIndex].y;
                    case 2: return CONST[regIndex].z;
                    case 3: return CONST[regIndex].w;

                    default: return null; // to silence compiler warning
                }
            }
        }

        return null;
    }

    protected function getVertexAttribute(name:String):IRegister {
        if(_currentProgramType != ConstantType.VERTEX)
            throw new IllegalOperationError("attribute registers are available for vertex programs only");

        var index:int = _vertexFormat.getPropertyIndex(name);

        return ATTRIBUTE[index];
    }

    protected function vertexShaderCode():void {
        throw new Error("abstract method call");
    }

    protected function fragmentShaderCode():void {
        throw new Error("abstract method call");
    }

    override protected function _vertexShader():void {
        _currentProgramType = ConstantType.VERTEX;

        vertexShaderCode();
    }

    override protected function _fragmentShader():void {
        _currentProgramType = ConstantType.FRAGMENT;

        fragmentShaderCode();
    }

    /** Creates new vertex- and index-buffers and uploads our vertex- and index-data into these buffers. */
    private function createBuffers():void {
        var context:Context3D = Starling.context;
        if (context == null) throw new MissingContextError();

        _buffersDirty = false;

        if (_vertexBuffer) _vertexBuffer.dispose();
        if (_indexBuffer)  _indexBuffer.dispose();

        _vertexBuffer = context.createVertexBuffer(vertexCount, _vertexFormat.totalSize);
        _vertexBuffer.uploadFromVector(_vertexRawData, 0, vertexCount);

        _indexBuffer = context.createIndexBuffer(_triangleData.length);
        _indexBuffer.uploadFromVector(mIndexData, 0, _triangleData.length);
    }

    private function setOrthographicProjection(x:Number, y:Number, width:Number, height:Number):Matrix3D {
        _projectionMatrix.setTo(
            2.0 / width, 0, 0,
            -2.0 / height, -(2 * x + width) / width, (2 * y + height) / height
        );

        return MatrixUtil.convertTo3D(_projectionMatrix, _matrix3D);
    }

    private function setProgramConstants(context:Context3D, vertexIndex:int, fragmentIndex:int):void {
        var i:int, count:int;

        count = _registerConstants.length;
        for(i = 0; i < count; ++i) {
            var regConstant:RegisterConstant = _registerConstants[i];

            if(regConstant.type == ConstantType.VERTEX) {
                context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, vertexIndex, regConstant.values, 1);
                ++vertexIndex;
            }
            else {
                context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, fragmentIndex, regConstant.values, 1);
                ++fragmentIndex;
            }
        }

        _vertexConstants.length     = 0;
        _fragmentConstants.length   = 0;

        for(i = 0; i < count; ++i) {
            var compConstant:ComponentConstant = _componentConstants[i];

            if(compConstant.type == ConstantType.VERTEX)
                _vertexConstants[_vertexConstants.length] = compConstant.value;
            else
                _fragmentConstants[_fragmentConstants.length] = compConstant.value;
        }

        if(_vertexConstants.length > 0) {
            var vertexRegs:int = (_vertexConstants.length % 4) == 0
                ? _vertexConstants.length / 4
                : _vertexConstants.length / 4 + 1
            ;

            context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, vertexIndex, _vertexConstants, vertexRegs);
        }

        if(_fragmentConstants.length > 0) {
            var fragmentRegs:int = (_fragmentConstants.length % 4) == 0
                ? _fragmentConstants.length / 4
                : _fragmentConstants.length / 4 + 1
            ;

            context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, fragmentIndex, _fragmentConstants, fragmentRegs);
        }
    }

    private function setInputTextures(context:Context3D):void {
        var count:int = _inputTextures.length;
        for(var i:int = 0; i < count; i++) {
            var texture:Texture = _inputTextures[i];

            context.setTextureAt(i, texture.base);
        }
    }

    private function unsetInputTextures(context:Context3D):void {
        var count:int = _inputTextures.length;
        for(var i:int = 0; i < count; i++) {
            var texture:Texture = _inputTextures[i];

            context.setTextureAt(i, null);
        }
    }

    private function setVertexBuffers(context:Context3D):void {
        var count:int = _vertexFormat.propertyCount;
        for(var i:int = 0; i < count; i++) {
            var size:int    = _vertexFormat.getSize(i);
            var offset:int  = _vertexFormat.getOffset(i);

            var bufferFormat:String;

            switch(size) {
                case 1: bufferFormat = Context3DVertexBufferFormat.FLOAT_1; break;
                case 2: bufferFormat = Context3DVertexBufferFormat.FLOAT_2; break;
                case 3: bufferFormat = Context3DVertexBufferFormat.FLOAT_3; break;
                case 4: bufferFormat = Context3DVertexBufferFormat.FLOAT_4; break;

                default:
                    throw new Error("vertex data size invalid (" + size + ") for data index: " + i);
            }

            context.setVertexBufferAt(i, _vertexBuffer, offset, bufferFormat);
        }
    }

    private function unsetVertexBuffers(context:Context3D):void {
        var count:int = _vertexFormat.propertyCount;
        for(var i:int = 0; i < count; i++)
            context.setVertexBufferAt(i, null);
    }
}
}