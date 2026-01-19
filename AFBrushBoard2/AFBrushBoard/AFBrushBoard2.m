/*
 File: PaintingView.m
 Abstract: The class responsible for the finger painting. The class wraps the
 CAEAGLLayer from CoreAnimation into a convenient UIView subclass. The view
 content is basically an EAGL surface you render your OpenGL scene into.
 Version: 1.13
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
 */

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>
#import <GLKit/GLKit.h>

#import "AFBrushBoard2.h"
#import "shaderUtil.h"
#import "fileUtil.h"
#import "debug.h"
#import "AFPointsManager.h"

//CONSTANTS:

#define kBrushOpacity           (1.0 / 3)
#define kBrushPixelStep         1
#define kBrushScale             5
#define kInitialVertexBufferSize 64
#define kClearColorWhite        1.0
#define kBatchSizeTolerance     0.5f


// Shaders
enum {
    PROGRAM_POINT,
    NUM_PROGRAMS
};

enum {
    UNIFORM_MVP,
    UNIFORM_POINT_SIZE,
    UNIFORM_VERTEX_COLOR,
    UNIFORM_TEXTURE,
    NUM_UNIFORMS
};

enum {
    ATTRIB_VERTEX,
    NUM_ATTRIBS
};

typedef struct {
    char *vert, *frag;
    GLint uniform[NUM_UNIFORMS];
    GLuint id;
} programInfo_t;

programInfo_t program[NUM_PROGRAMS] = {
    { "point.vsh",   "point.fsh" },     // PROGRAM_POINT
};


// Texture
typedef struct {
    GLuint id;
    GLsizei width, height;
} textureInfo_t;


@interface AFBrushBoard2()
{
    // The pixel dimensions of the backbuffer
    GLint backingWidth;
    GLint backingHeight;

    EAGLContext *context;

    // OpenGL names for the renderbuffer and framebuffers used to render to this view
    GLuint viewRenderbuffer, viewFramebuffer;

    textureInfo_t brushTexture;     // brush texture
    GLfloat brushColor[4];          // brush color

    Boolean needsErase;

    // Shader objects
    GLuint vertexShader;
    GLuint fragmentShader;
    GLuint shaderProgram;

    // Buffer Objects
    GLuint vboId;

    BOOL initialized;
}
@property AFPointsManager *pointManager;
@end

@implementation AFBrushBoard2

@synthesize  location;

// Implement this to override the default layer class (which is [CALayer class]).
// We do this so that our view will be backed by a layer that is capable of OpenGL ES rendering.
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

// The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)initWithFrame:(CGRect)frame {

    if ((self = [super initWithFrame:frame])) {
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;

        eaglLayer.opaque = YES;
        // In this application, we want to retain the EAGLDrawable contents after a call to presentRenderbuffer.
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:YES], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];

        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

        if (!context || ![EAGLContext setCurrentContext:context]) {
            return nil;
        }

        // Set the view's scale factor as you wish
        self.contentScaleFactor = [[UIScreen mainScreen] scale];

        // Make sure to start with a cleared buffer
        needsErase = YES;
        self.pointManager = [AFPointsManager new];
    }

    return self;
}

// If our view is resized, we'll be asked to layout subviews.
// This is the perfect opportunity to also update the framebuffer so that it is
// the same size as our display area.
-(void)layoutSubviews
{
    [EAGLContext setCurrentContext:context];

    if (!initialized) {
        initialized = [self initGL];
    }

    // Clear the framebuffer the first time it is allocated
    if (needsErase) {
        [self erase];
        needsErase = NO;
    }
}

// Load and compile a shader program
- (BOOL)loadAndCompileProgram:(int)programIndex
{
    char *vsrc = readFile(pathForResource(program[programIndex].vert));
    char *fsrc = readFile(pathForResource(program[programIndex].frag));

    // Check if shader files were loaded successfully
    if (vsrc == NULL) {
        NSLog(@"Failed to read vertex shader file: %s", program[programIndex].vert);
        return NO;
    }
    if (fsrc == NULL) {
        NSLog(@"Failed to read fragment shader file: %s", program[programIndex].frag);
        free(vsrc);
        return NO;
    }

    GLsizei attribCt = 0;
    GLchar *attribUsed[NUM_ATTRIBS];
    GLint attrib[NUM_ATTRIBS];
    GLchar *attribName[NUM_ATTRIBS] = {
        "inVertex",
    };
    const GLchar *uniformName[NUM_UNIFORMS] = {
        "MVP", "pointSize", "vertexColor", "texture",
    };

    // Auto-assign known attributes
    for (int j = 0; j < NUM_ATTRIBS; j++) {
        if (strstr(vsrc, attribName[j])) {
            attrib[attribCt] = j;
            attribUsed[attribCt++] = attribName[j];
        }
    }

    glueCreateProgram(vsrc, fsrc,
                      attribCt, (const GLchar **)&attribUsed[0], attrib,
                      NUM_UNIFORMS, &uniformName[0], program[programIndex].uniform,
                      &program[programIndex].id);
    free(vsrc);
    free(fsrc);

    return YES;
}

// Set up uniforms for the point drawing program
- (void)setupPointProgramUniforms
{
    glUseProgram(program[PROGRAM_POINT].id);

    // The brush texture will be bound to texture unit 0
    glUniform1i(program[PROGRAM_POINT].uniform[UNIFORM_TEXTURE], 0);

    // Setup viewing matrices
    GLKMatrix4 projectionMatrix = GLKMatrix4MakeOrtho(0, backingWidth, 0, backingHeight, -1, 1);
    GLKMatrix4 modelViewMatrix = GLKMatrix4Identity;
    GLKMatrix4 MVPMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);

    glUniformMatrix4fv(program[PROGRAM_POINT].uniform[UNIFORM_MVP], 1, GL_FALSE, MVPMatrix.m);

    // Set point size
    glUniform1f(program[PROGRAM_POINT].uniform[UNIFORM_POINT_SIZE], brushTexture.width / kBrushScale);

    // Initialize brush color
    glUniform4fv(program[PROGRAM_POINT].uniform[UNIFORM_VERTEX_COLOR], 1, brushColor);
}

- (void)setupShaders
{
    for (int i = 0; i < NUM_PROGRAMS; i++) {
        if (![self loadAndCompileProgram:i]) {
            continue;
        }

        // Set up program-specific uniforms
        if (i == PROGRAM_POINT) {
            [self setupPointProgramUniforms];
        }
    }

    glError();
}

// Create a texture from an image
- (textureInfo_t)textureFromName:(NSString *)name
{
    CGImageRef        brushImage;
    CGContextRef    brushContext;
    GLubyte            *brushData;
    size_t            width, height;
    GLuint          texId;
    textureInfo_t   texture;
    
    // First create a UIImage object from the data in a image file, and then extract the Core Graphics image
    brushImage = [UIImage imageNamed:name].CGImage;
    
    // Get the width and height of the image
    width = CGImageGetWidth(brushImage);
    height = CGImageGetHeight(brushImage);
    
    // Make sure the image exists
    if(brushImage) {
        // Allocate  memory needed for the bitmap context
        brushData = (GLubyte *) calloc(width * height * 4, sizeof(GLubyte));
        if (brushData == NULL) {
            NSLog(@"Failed to allocate memory for brush texture data");
            texture.id = 0;
            texture.width = 0;
            texture.height = 0;
            return texture;
        }

        // Use  the bitmatp creation function provided by the Core Graphics framework.
        brushContext = CGBitmapContextCreate(brushData, width, height, 8, width * 4, CGImageGetColorSpace(brushImage), kCGImageAlphaPremultipliedLast);
        if (brushContext == NULL) {
            NSLog(@"Failed to create bitmap context for brush texture");
            free(brushData);
            texture.id = 0;
            texture.width = 0;
            texture.height = 0;
            return texture;
        }

        // After you create the context, you can draw the  image to the context.
        CGContextDrawImage(brushContext, CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height), brushImage);
        // You don't need the context at this point, so you need to release it to avoid memory leaks.
        CGContextRelease(brushContext);
        // Use OpenGL ES to generate a name for the texture.
        glGenTextures(1, &texId);
        // Bind the texture name.
        glBindTexture(GL_TEXTURE_2D, texId);
        // Set the texture parameters to use a minifying filter and a linear filer (weighted average)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        // Specify a 2D texture image, providing the a pointer to the image data in memory
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)width, (int)height, 0, GL_RGBA, GL_UNSIGNED_BYTE, brushData);
        // Release  the image data; it's no longer needed
        free(brushData);

        texture.id = texId;
        texture.width = (int)width;
        texture.height = (int)height;
    }else{
        NSLog(@"Failed to load brush image: %@", name);
        texture.id = 0;
        texture.width = 0;
        texture.height = 0;
    }
    
    return texture;
}

- (BOOL)initGL
{
    // Generate IDs for a framebuffer object and a color renderbuffer
    glGenFramebuffers(1, &viewFramebuffer);
    glGenRenderbuffers(1, &viewRenderbuffer);
    
    glBindFramebuffer(GL_FRAMEBUFFER, viewFramebuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, viewRenderbuffer);
    // This call associates the storage for the current render buffer with the EAGLDrawable (our CAEAGLLayer)
    // allowing us to draw into a buffer that will later be rendered to screen wherever the layer is (which corresponds with our view).
    [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(id<EAGLDrawable>)self.layer];
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, viewRenderbuffer);
    
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    
    // For this sample, we do not need a depth buffer. If you do, this is how you can create one and attach it to the framebuffer:
    //    glGenRenderbuffers(1, &depthRenderbuffer);
    //    glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
    //    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, backingWidth, backingHeight);
    //    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
    
    if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
        return NO;
    }
    
    // Setup the view port in Pixels
    glViewport(0, 0, backingWidth, backingHeight);
    
    // Create a Vertex Buffer Object to hold our data
    glGenBuffers(1, &vboId);
    
    // Load the brush texture
    brushTexture = [self textureFromName:@"Shape.png"];
    
    // Load shaders
    [self setupShaders];
    
    // Enable blending and set a blending function appropriate for premultiplied alpha pixel data
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    return YES;
}

- (BOOL)resizeFromLayer:(CAEAGLLayer *)layer
{
    // Allocate color buffer backing based on the current layer size
    glBindRenderbuffer(GL_RENDERBUFFER, viewRenderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    
    // For this sample, we do not need a depth buffer. If you do, this is how you can allocate depth buffer backing:
    //    glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
    //    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, backingWidth, backingHeight);
    //    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
    
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"Failed to make complete framebuffer objectz %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
        return NO;
    }
    
    // Update projection matrix
    GLKMatrix4 projectionMatrix = GLKMatrix4MakeOrtho(0, backingWidth, 0, backingHeight, -1, 1);
    GLKMatrix4 modelViewMatrix = GLKMatrix4Identity; // this sample uses a constant identity modelView matrix
    GLKMatrix4 MVPMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
    
    glUseProgram(program[PROGRAM_POINT].id);
    glUniformMatrix4fv(program[PROGRAM_POINT].uniform[UNIFORM_MVP], 1, GL_FALSE, MVPMatrix.m);
    
    // Update viewport
    glViewport(0, 0, backingWidth, backingHeight);
    
    return YES;
}

// Releases resources when they are not longer needed.
- (void)dealloc
{
    // Destroy framebuffers and renderbuffers
    if (viewFramebuffer) {
        glDeleteFramebuffers(1, &viewFramebuffer);
        viewFramebuffer = 0;
    }
    if (viewRenderbuffer) {
        glDeleteRenderbuffers(1, &viewRenderbuffer);
        viewRenderbuffer = 0;
    }
    // texture
    if (brushTexture.id) {
        glDeleteTextures(1, &brushTexture.id);
        brushTexture.id = 0;
    }
    // vbo
    if (vboId) {
        glDeleteBuffers(1, &vboId);
        vboId = 0;
    }

    // tear down context
    if ([EAGLContext currentContext] == context)
        [EAGLContext setCurrentContext:nil];
}

// Helper method to set up GL context and framebuffer
- (void)setupGLContext
{
    [EAGLContext setCurrentContext:context];
    glBindFramebuffer(GL_FRAMEBUFFER, viewFramebuffer);
}

// Helper method to present the rendered content
- (void)presentRenderbuffer
{
    glBindRenderbuffer(GL_RENDERBUFFER, viewRenderbuffer);
    [context presentRenderbuffer:GL_RENDERBUFFER];
}

// Helper method to convert touch coordinates from UIView to OpenGL coordinate system
- (CGPoint)convertTouchPoint:(CGPoint)touchPoint
{
    CGRect bounds = [self bounds];
    touchPoint.y = bounds.size.height - touchPoint.y;
    return touchPoint;
}

// Erases the screen
- (void)erase
{
    [self setupGLContext];

    // Clear the buffer to white
    glClearColor(kClearColorWhite, kClearColorWhite, kClearColorWhite, kClearColorWhite);
    glClear(GL_COLOR_BUFFER_BIT);

    // Display the buffer
    [self presentRenderbuffer];
}

// Handles the start of a touch
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [[event touchesForView:self] anyObject];

    // Convert touch point from UIView referential to OpenGL one (upside-down flip)
    location = [self convertTouchPoint:[touch locationInView:self]];
    [self.pointManager startWithPoint:location];
}

// Handles the continuation of a touch.
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [[event touchesForView:self] anyObject];

    // Convert touch point from UIView referential to OpenGL one (upside-down flip)
    location = [self convertTouchPoint:[touch locationInView:self]];

    // Render the stroke
    NSArray *points = [self.pointManager appendPoint:location];
    [self drawPoints:points];
}

// Handles the end of a touch event when the touch is a tap.
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [[event touchesForView:self] anyObject];

    // Convert touch point from UIView referential to OpenGL one (upside-down flip)
    location = [self convertTouchPoint:[touch locationInView:self]];
    NSArray *points = [self.pointManager finishWithPoint:location];
    [self drawPoints:points];
}

// Handles the end of a touch event.
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    // If appropriate, add code necessary to save the state of the application.
    // This application is not saving state.
}


- (void)drawPoints:(NSArray *)points{
    if (points.count == 0) {
        return;
    }

    [self setupGLContext];

    // Convert scale factor once
    CGFloat scale = self.contentScaleFactor;

    // Allocate vertex buffer for all points at once
    GLfloat *vertexBuffer = malloc(points.count * 2 * sizeof(GLfloat));
    if (vertexBuffer == NULL) {
        NSLog(@"Failed to allocate vertex buffer for %lu points", (unsigned long)points.count);
        return;
    }

    // Fill vertex buffer with all points and convert coordinates
    for (int i = 0; i < points.count; i++) {
        AFPoint *point = points[i];
        CGPoint p = point.point;

        // Convert locations from Points to Pixels
        vertexBuffer[i * 2 + 0] = p.x * scale;
        vertexBuffer[i * 2 + 1] = p.y * scale;
    }

    // Set up GL state once (outside the loop)
    glBindBuffer(GL_ARRAY_BUFFER, vboId);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 0, 0);
    glUseProgram(program[PROGRAM_POINT].id);

    // Batch draw points with same size to reduce GL calls
    int startIdx = 0;
    while (startIdx < points.count) {
        AFPoint *currentPoint = points[startIdx];
        GLfloat currentSize = currentPoint.size;
        int batchCount = 1;

        // Find consecutive points with similar size
        while (startIdx + batchCount < points.count) {
            AFPoint *nextPoint = points[startIdx + batchCount];
            if (fabsf(nextPoint.size - currentSize) < kBatchSizeTolerance) {
                batchCount++;
            } else {
                break;
            }
        }

        // Upload vertex data for this batch
        glBufferData(GL_ARRAY_BUFFER, batchCount * 2 * sizeof(GLfloat),
                     &vertexBuffer[startIdx * 2], GL_DYNAMIC_DRAW);

        // Set point size for this batch
        glUniform1f(program[PROGRAM_POINT].uniform[UNIFORM_POINT_SIZE], currentSize);

        // Draw all points in this batch
        glDrawArrays(GL_POINTS, 0, batchCount);

        startIdx += batchCount;
    }

    // Clean up vertex buffer
    free(vertexBuffer);

    // Display the buffer once after all points are drawn
    [self presentRenderbuffer];
}

- (void)setBrushColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
{
    // Update the brush color with premultiplied alpha
    brushColor[0] = red * kBrushOpacity;
    brushColor[1] = green * kBrushOpacity;
    brushColor[2] = blue * kBrushOpacity;
    brushColor[3] = kBrushOpacity;

    if (initialized) {
        glUseProgram(program[PROGRAM_POINT].id);
        glUniform4fv(program[PROGRAM_POINT].uniform[UNIFORM_VERTEX_COLOR], 1, brushColor);
    }
}


- (BOOL)canBecomeFirstResponder {
    return YES;
}

@end
