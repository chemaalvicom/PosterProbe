#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Ejecuta un bloque capturando excepciones Objective-C (Swift no puede).
/// Devuelve nil si fue bien, o la descripción de la excepción.
@interface ObjCCatch : NSObject
+ (nullable NSString *)run:(NS_NOESCAPE void (^)(void))block NS_SWIFT_NAME(run(_:));
/// value(forKey:) protegido: devuelve el valor o nil, y el error en `error`.
+ (nullable id)valueOf:(id)object forKey:(NSString *)key error:(NSString * _Nullable * _Nullable)error NS_SWIFT_NAME(value(of:forKey:error:));
/// Nombres de propiedades declaradas en la clase y sus superclases (hasta NSObject).
+ (NSArray<NSString *> *)propertyNamesOfClass:(Class)cls NS_SWIFT_NAME(propertyNames(of:));
/// Nombres de métodos de instancia sin argumentos (posibles getters).
+ (NSArray<NSString *> *)getterNamesOfClass:(Class)cls NS_SWIFT_NAME(getterNames(of:));
@end

NS_ASSUME_NONNULL_END
