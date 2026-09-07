fn main() {
    #[cfg(target_os = "macos")]
    {
        cc::Build::new()
            .file("metal/metal_bridge.m")
            .flag("-fobjc-arc")
            .compile("metal_bridge");

        println!("cargo:rustc-link-lib=framework=Metal");
        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rerun-if-changed=metal/metal_bridge.m");
        println!("cargo:rerun-if-changed=metal/metal_bridge.h");
        println!("cargo:rerun-if-changed=metal/rtx.metal");
    }
    println!("cargo:rerun-if-changed=shaders/rtx.wgsl");
}
