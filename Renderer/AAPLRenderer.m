/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of a platform independent renderer class, which performs Metal setup and per frame rendering
*/

@import simd;
@import MetalKit;

#import "AAPLRenderer.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
// uses these types as inputs to the shaders.
#import "AAPLShaderTypes.h"

// Main class performing the rendering
@implementation AAPLRenderer
{
    id<MTLDevice> _device;

    MTLRenderPassDescriptor *_renderPassDescriptor;

    // The render pipeline generated from the vertex and fragment shaders in the .metal shader file.
    id<MTLRenderPipelineState> _pipelineState;

    id<MTLDepthStencilState> _depthStencilState;

    id<MTLTexture> _depthStencilTexture;

    MTLRenderPassDescriptor *_presentRenderPassDescriptor;

    id<MTLRenderPipelineState> _presentPipelineState;

    id<MTLDepthStencilState> _presentDepthStencilState;

    // The command queue used to pass commands to the device.
    id<MTLCommandQueue> _commandQueue;

    // The current size of the view, used as an input to the vertex shader.
    vector_uint2 _viewportSize;
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        NSError *error;

        _device = mtkView.device;

        MTLRenderPassDepthAttachmentDescriptor *depthAttachment = [[MTLRenderPassDepthAttachmentDescriptor alloc] init];
        depthAttachment.loadAction = MTLLoadActionClear;
        depthAttachment.storeAction = MTLStoreActionDontCare;
        depthAttachment.clearDepth = 0.5;

        MTLRenderPassStencilAttachmentDescriptor *stencilAttachment = [[MTLRenderPassStencilAttachmentDescriptor alloc] init];
        stencilAttachment.loadAction = MTLLoadActionClear;
        stencilAttachment.storeAction = MTLStoreActionStore;
        stencilAttachment.clearStencil = 0;

        _renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
        _renderPassDescriptor.depthAttachment = depthAttachment;
        _renderPassDescriptor.stencilAttachment = stencilAttachment;

        // Load all the shader files with a .metal file extension in the project.
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

        // Configure a pipeline descriptor that is used to create a pipeline state.
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        pipelineStateDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                 error:&error];
                
        // Pipeline State creation could fail if the pipeline descriptor isn't set up properly.
        //  If the Metal API validation is enabled, you can find out more information about what
        //  went wrong.  (Metal API validation is enabled by default when a debug build is run
        //  from Xcode.)
        NSAssert(_pipelineState, @"Failed to create pipeline state: %@", error);

        MTLStencilDescriptor *stencilDescriptor = [[MTLStencilDescriptor alloc] init];
        stencilDescriptor.stencilCompareFunction = MTLCompareFunctionAlways;
        stencilDescriptor.stencilFailureOperation = MTLStencilOperationKeep;
        stencilDescriptor.depthFailureOperation = MTLStencilOperationReplace;
        stencilDescriptor.depthStencilPassOperation = MTLStencilOperationInvert;
        stencilDescriptor.readMask = 0;
        stencilDescriptor.writeMask = 0xFFFFFFFF;

        MTLDepthStencilDescriptor *depthStencilDescriptor = [[MTLDepthStencilDescriptor alloc] init];
        depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionLess;
        depthStencilDescriptor.depthWriteEnabled = NO;
        depthStencilDescriptor.frontFaceStencil = stencilDescriptor;

        _depthStencilState = [_device newDepthStencilStateWithDescriptor:depthStencilDescriptor];

        {
            MTLRenderPassColorAttachmentDescriptor *colorAttachment = [[MTLRenderPassColorAttachmentDescriptor alloc] init];
            colorAttachment.loadAction = MTLLoadActionClear;
            colorAttachment.storeAction = MTLStoreActionStore;
            colorAttachment.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);

            MTLRenderPassStencilAttachmentDescriptor *stencilAttachment = [[MTLRenderPassStencilAttachmentDescriptor alloc] init];
            stencilAttachment.loadAction = MTLLoadActionLoad;
            stencilAttachment.storeAction = MTLStoreActionDontCare;

            _presentRenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
            _presentRenderPassDescriptor.colorAttachments[0] = colorAttachment;
            _presentRenderPassDescriptor.stencilAttachment = stencilAttachment;

            id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"presentFragmentShader"];
            
            // Configure a pipeline descriptor that is used to create a pipeline state.
            MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
            pipelineStateDescriptor.vertexFunction = vertexFunction;
            pipelineStateDescriptor.fragmentFunction = fragmentFunction;
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
            pipelineStateDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
            
            _presentPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                     error:&error];

            MTLStencilDescriptor *stencilDescriptor = [[MTLStencilDescriptor alloc] init];
            stencilDescriptor.stencilCompareFunction = MTLCompareFunctionEqual;
            stencilDescriptor.readMask = 0xFFFFFFFF;
            stencilDescriptor.writeMask = 0;

            MTLDepthStencilDescriptor *depthStencilDescriptor = [[MTLDepthStencilDescriptor alloc] init];
            depthStencilDescriptor.frontFaceStencil = stencilDescriptor;

            _presentDepthStencilState = [_device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
        }

        // Create the command queue
        _commandQueue = [_device newCommandQueue];
    }

    return self;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable to pass to the vertex shader.
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;

    MTLTextureDescriptor *textureDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float_Stencil8 width:size.width height:size.height mipmapped:false];
    textureDescriptor.resourceOptions = MTLResourceStorageModePrivate;
    textureDescriptor.usage = MTLTextureUsageRenderTarget;

    _depthStencilTexture = [_device newTextureWithDescriptor:textureDescriptor];

    _renderPassDescriptor.depthAttachment.texture = _depthStencilTexture;
    _renderPassDescriptor.stencilAttachment.texture = _depthStencilTexture;
    
    _presentRenderPassDescriptor.stencilAttachment.texture = _depthStencilTexture;
}

/// Called whenever the view needs to render a frame.
- (void)drawInMTKView:(nonnull MTKView *)view
{
    // Create a new command buffer for each render pass to the current drawable.
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";

    {
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_renderPassDescriptor];
        renderEncoder.label = @"Write stencil";
        
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, _viewportSize.x, _viewportSize.y, 0.0, 1.0 }];
        
        [renderEncoder setRenderPipelineState:_pipelineState];
        
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        
        [renderEncoder setDepthStencilState:_depthStencilState];
        
        [renderEncoder setStencilReferenceValue:128];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:3];
        
        [renderEncoder endEncoding];
    }


    {
        _presentRenderPassDescriptor.colorAttachments[0].texture = view.currentDrawable.texture;
        
        // Create a render command encoder.
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:_presentRenderPassDescriptor];
        renderEncoder.label = @"present";
        
        // Set the region of the drawable to draw into.
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, _viewportSize.x, _viewportSize.y, 0.0, 1.0 }];
        
        [renderEncoder setRenderPipelineState:_presentPipelineState];
        
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];

        [renderEncoder setDepthStencilState:_presentDepthStencilState];

        [renderEncoder setStencilReferenceValue:128];
        
        // Draw the triangle.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:3];
        
        [renderEncoder endEncoding];
    }

    // Schedule a present once the framebuffer is complete using the current drawable.
    [commandBuffer presentDrawable:view.currentDrawable];

    // Finalize rendering here & push the command buffer to the GPU.
    [commandBuffer commit];
}

@end
