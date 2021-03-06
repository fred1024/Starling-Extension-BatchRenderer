/**
 * User: booster
 * Date: 04/05/14
 * Time: 12:46
 */
package starling.renderer.examples.colored {
import starling.renderer.geometry.GeometryData;

public class ColoredGeometryData extends GeometryData {
    public function ColoredGeometryData() {
        super(ColoredGeometryVertexFormat.cachedInstance);
    }

    public function getVertexColor(vertex:int, color:Vector.<Number> = null):Vector.<Number> { return getVertexData(vertex, ColoredGeometryVertexFormat.cachedInstance.colorID, color); }
    public function setVertexColor(vertex:int, r:Number, g:Number, b:Number, a:Number):void { setVertexData(vertex, ColoredGeometryVertexFormat.cachedInstance.colorID, r, g, b, a); }
}
}
