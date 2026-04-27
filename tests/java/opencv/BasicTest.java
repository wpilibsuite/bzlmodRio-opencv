package opencv;

import org.junit.jupiter.api.Test;
import org.opencv.core.Core;
import org.opencv.core.CvType;
import org.opencv.core.Mat;

class BasicTest {
  @SuppressWarnings("restricted")
  @Test
  void basicTest() {
    System.out.println("Hello World");
    System.out.println(System.getProperty("user.dir"));

    System.loadLibrary(Core.NATIVE_LIBRARY_NAME);
    Mat mat = Mat.eye(3, 3, CvType.CV_8UC1);
    System.out.println("mat = " + mat.dump());
  }
}
